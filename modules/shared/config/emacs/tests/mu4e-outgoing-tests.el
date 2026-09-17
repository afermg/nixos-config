;;; mu4e-outgoing-tests.el --- Outgoing mail checks -*- lexical-binding: t; -*-

;; Run without user init or sending mail:
;; emacs --batch -Q -L ~/.nix-profile/share/emacs/site-lisp/mu4e \
;;   -l modules/shared/config/emacs/tests/mu4e-outgoing-tests.el \
;;   -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'mu4e)

(let ((config (expand-file-name "../config.org" (file-name-directory load-file-name)))
      (names '(afm/message-auto-fix-continuation-headers
               afm/mu4e-verify-from-before-send afm/mu4e-my-addresses))
      (loaded 0))
  (with-temp-buffer
    (insert-file-contents config)
    (search-forward "(use-package mu4e\n")
    (goto-char (match-beginning 0))
    (dolist (form (cddr (read (current-buffer))))
      (when (and (consp form) (memq (car form) '(defun defvar))
                 (memq (cadr form) names))
        (eval form t)
        (cl-incf loaded))))
  (unless (= loaded (length names)) (error "Missing outgoing-mail definitions")))

(defmacro afm/test-outgoing (from to cc canonical &rest body)
  "Run BODY against synthetic headers, mocking history and confirmation."
  (declare (indent 4))
  `(with-temp-buffer
     (let ((prompts 0) (answer nil))
       (setq major-mode 'message-mode)
       (insert (format "From: %s\nTo: %s\nCc: %s\n\nTest body\n" ,from ,to ,cc))
       (cl-letf (((symbol-function 'afm/mu4e--canonical-from-for)
                  (lambda (&rest _) ,canonical))
                 ((symbol-function 'y-or-n-p)
                  (lambda (&rest _) (cl-incf prompts) answer)))
         ,@body))))

(ert-deftest afm/outgoing-purdue-to-broad-skips-obsolete-history-prompt ()
  (afm/test-outgoing "amunozgo@purdue.edu" "colleague@broadinstitute.org" ""
      "amunozgo@broadinstitute.org"
    (afm/mu4e-verify-from-before-send)
    (should (= prompts 0))))

(ert-deftest afm/outgoing-broad-sender-remains-valid ()
  (afm/test-outgoing "amunozgo@broadinstitute.org" "colleague@broadinstitute.org" ""
      "amunozgo@broadinstitute.org"
    (afm/mu4e-verify-from-before-send)
    (should (= prompts 0))))

(ert-deftest afm/outgoing-personal-from-to-broad-is-blocked ()
  (afm/test-outgoing "alan@quasimorphic.com" "colleague@broadinstitute.org" "" nil
    (setq answer t)
    (should-error (afm/mu4e-verify-from-before-send) :type 'user-error)
    (should (= prompts 0))))

(ert-deftest afm/outgoing-personal-from-with-broad-cc-is-blocked ()
  (afm/test-outgoing "alan@quasimorphic.com" "other@example.com" "colleague@broadinstitute.org" nil
    (should-error (afm/mu4e-verify-from-before-send) :type 'user-error)))

(ert-deftest afm/outgoing-other-history-mismatch-still-requires-confirmation ()
  (afm/test-outgoing "amunozgo@purdue.edu" "other@example.com" "" "alan@quasimorphic.com"
    (should-error (afm/mu4e-verify-from-before-send) :type 'user-error)
    (should (= prompts 1))
    (setq answer t)
    (afm/mu4e-verify-from-before-send)
    (should (= prompts 2))))

(ert-deftest afm/outgoing-only-continuation-repair-is-auto-approved ()
  (let (prompts)
    (cl-letf (((symbol-function 'y-or-n-p)
               (lambda (prompt) (push prompt prompts) nil)))
      (should
       (afm/message-auto-fix-continuation-headers
        (lambda () (y-or-n-p "Fix continuation lines? "))))
      (should-not prompts)
      (should-not
       (afm/message-auto-fix-continuation-headers
        (lambda () (y-or-n-p "Send despite missing subject? "))))
      (should (equal prompts '("Send despite missing subject? "))))))

(ert-deftest afm/outgoing-header-wrapper-preserves-arguments-and-errors ()
  (should (equal (afm/message-auto-fix-continuation-headers #'list 1 2) '(1 2)))
  (should-error
   (afm/message-auto-fix-continuation-headers (lambda () (error "Header error")))
   :type 'error))

;;; mu4e-outgoing-tests.el ends here
