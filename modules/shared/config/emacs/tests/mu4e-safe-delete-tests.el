;;; mu4e-safe-delete-tests.el --- Safe deletion regression tests -*- lexical-binding: t; -*-

;; Run without a mail server or user init:
;; emacs --batch -Q -L ~/.nix-profile/share/emacs/site-lisp/mu4e \
;;   -l modules/shared/config/emacs/tests/mu4e-safe-delete-tests.el \
;;   -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'mu4e)

;; Load only this policy's definitions, never the user's whole configuration.
(let ((config (expand-file-name "../config.org" (file-name-directory load-file-name)))
      (names '(afm/mu4e-trash-folder afm/mu4e-require-trash
               afm/mu4e-delete-trash-target afm/mu4e-delete-from-trash
               afm/mu4e-confirm-trash-deletions afm/mu4e-install-safe-delete
               afm/mu4e--confirmed-delete-docids))
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
  (unless (= loaded (length names)) (error "Missing safe-delete definitions")))
(afm/mu4e-install-safe-delete)

(defmacro afm/test-with-marks (messages marks &rest body)
  "Run BODY with fake MESSAGES and MARKS; all server mutations are mocked."
  (declare (indent 2))
  `(with-temp-buffer
     (let* ((data ,messages)
            (mu4e--mark-map (make-hash-table))
            (mu4e-headers-show-target nil)
            (afm/mu4e--confirmed-delete-docids nil)
            (header-buffer (current-buffer))
            (fake-msg (cdar data))
            (removed nil) (moved nil)
            (confirmations 0) (generic-confirmations 0)
            (allow-delete nil) (allow-generic t))
       (setq major-mode 'mu4e-headers-mode)
       (dolist (pair ,marks) (puthash (car pair) (cdr pair) mu4e--mark-map))
       (cl-letf (((symbol-function 'mu4e-current-buffer-type-p)
                  (lambda (kind) (eq major-mode (pcase kind ('headers 'mu4e-headers-mode) ('view 'mu4e-view-mode)))))
                 ((symbol-function 'mu4e-get-headers-buffer) (lambda () header-buffer))
                 ((symbol-function 'mu4e-message-at-point) (lambda (&rest _) fake-msg))
                 ((symbol-function 'mu4e~headers-goto-docid)
                  (lambda (docid &rest _) (setq fake-msg (alist-get docid data)) (and fake-msg (point-min))))
                 ((symbol-function 'mu4e~headers-mark) (lambda (docid &rest _) docid))
                 ((symbol-function 'mu4e-mark-unmark-all) (lambda (&rest _) (clrhash mu4e--mark-map)))
                 ((symbol-function 'yes-or-no-p)
                  (lambda (&rest _) (cl-incf confirmations) allow-delete))
                 ((symbol-function 'y-or-n-p)
                  (lambda (&rest _) (cl-incf generic-confirmations) allow-generic))
                 ((symbol-function 'mu4e--server-remove)
                  (lambda (docid &rest _) (push docid removed)))
                 ((symbol-function 'mu4e--server-move)
                  (lambda (docid target flags &rest _) (push (list docid target flags) moved)))
                 ((symbol-function 'mu4e--mark-check-target) #'identity))
         ,@body))))

(ert-deftest afm/delete-only-exact-account-trash ()
  (dolist (folder '("/quasimorphic/Trash" "/broad/[Gmail]/Trash" "/purdue/Deleted Items"))
    (should-not (afm/mu4e-require-trash (list :docid 1 :maildir folder) 1)))
  (dolist (folder '("/quasimorphic/Inbox" "/quasimorphic/Inbox/Purdue"
                    "/quasimorphic/Junk" "/quasimorphic/Trash/child"
                    "/quasimorphic/Trash-Other" "/broad/Inbox" "/purdue/Inbox" ""))
    (should-error (afm/mu4e-require-trash (list :docid 1 :maildir folder) 1) :type 'user-error))
  (should-error (afm/mu4e-require-trash nil) :type 'user-error))

(ert-deftest afm/delete-mark-blocked-outside-trash ()
  (afm/test-with-marks '((1 :docid 1 :maildir "/quasimorphic/Inbox")) nil
    (should-error (mu4e-mark-at-point 'delete nil) :type 'user-error)
    (should (= 0 (hash-table-count mu4e--mark-map)))
    (should-not removed)))

(ert-deftest afm/delete-mixed-batch-preflight-before-any-action ()
  (afm/test-with-marks '((1 :docid 1 :maildir "/quasimorphic/Trash")
                        (2 :docid 2 :maildir "/quasimorphic/Inbox"))
      '((1 delete) (2 delete))
    (setq allow-delete t)
    (should-error (mu4e-mark-execute-all t) :type 'user-error)
    (should (= 0 confirmations))
    (should-not removed)
    (should (= 2 (hash-table-count mu4e--mark-map)))))

(ert-deftest afm/delete-prefix-cannot-bypass-confirmation ()
  (afm/test-with-marks '((1 :docid 1 :maildir "/quasimorphic/Trash")) '((1 delete))
    (should-error (mu4e-mark-execute-all t) :type 'user-error)
    (should (= 1 confirmations))
    (should-not removed)
    (should (= 1 (hash-table-count mu4e--mark-map)))))

(ert-deftest afm/delete-batch-confirmed-once-and-trash-remains-recoverable ()
  (afm/test-with-marks '((1 :docid 1 :maildir "/quasimorphic/Trash")
                        (2 :docid 2 :maildir "/broad/[Gmail]/Trash")
                        (3 :docid 3 :maildir "/quasimorphic/Inbox"))
      '((1 delete) (2 delete) (3 trash . "/quasimorphic/Trash"))
    (setq allow-delete t)
    (mu4e-mark-execute-all)
    (should (= 1 confirmations))
    (should (= 0 generic-confirmations))
    (should (equal (sort removed #'<) '(1 2)))
    (should (equal moved '((3 "/quasimorphic/Trash" "-N"))))
    (should (= 0 (hash-table-count mu4e--mark-map)))))

(ert-deftest afm/delete-deferred-mark-cannot-bypass-guard ()
  (afm/test-with-marks '((1 :docid 1 :maildir "/quasimorphic/Inbox")) '((1 something))
    (cl-letf (((symbol-function 'mu4e--mark-get-markpair) (lambda (&rest _) '(delete))))
      (should-error (mu4e-mark-execute-all t) :type 'user-error))
    (should-not removed)))

(ert-deftest afm/delete-missing-message-fails-closed ()
  (afm/test-with-marks nil '((1 delete))
    (setq allow-delete t)
    (should-error (mu4e-mark-execute-all) :type 'user-error)
    (should-not removed)
    (should (= 0 confirmations))))

(ert-deftest afm/delete-direct-action-still-confirms ()
  (afm/test-with-marks '((1 :docid 1 :maildir "/quasimorphic/Trash")) nil
    (should-error (afm/mu4e-delete-from-trash 1 fake-msg nil) :type 'user-error)
    (should-not removed)
    (setq allow-delete t)
    (afm/mu4e-delete-from-trash 1 fake-msg nil)
    (should (equal removed '(1)))
    (should (= 2 confirmations))))

(ert-deftest afm/delete-direct-action-revalidates-folder-and-id ()
  (afm/test-with-marks '((1 :docid 1 :maildir "/quasimorphic/Inbox")) nil
    (setq allow-delete t)
    (let ((afm/mu4e--confirmed-delete-docids '(1)))
      (should-error (afm/mu4e-delete-from-trash 1 fake-msg nil) :type 'user-error))
    (should-error (afm/mu4e-delete-from-trash 2 '(:docid 1 :maildir "/quasimorphic/Trash") nil) :type 'user-error)
    (should-not removed)))

(ert-deftest afm/delete-folder-changed-after-confirmation-is-rejected ()
  (afm/test-with-marks '((1 :docid 1 :maildir "/quasimorphic/Trash")) '((1 delete))
    (cl-letf (((symbol-function 'yes-or-no-p)
               (lambda (&rest _) (setq data '((1 :docid 1 :maildir "/quasimorphic/Inbox"))) t)))
      (should-error (mu4e-mark-execute-all) :type 'user-error))
    (should-not removed)))

(ert-deftest afm/delete-policy-does-not-add-prompts-to-normal-trash ()
  (afm/test-with-marks '((1 :docid 1 :maildir "/quasimorphic/Inbox"))
      '((1 trash . "/quasimorphic/Trash"))
    (mu4e-mark-execute-all)
    (should (= 0 confirmations))
    (should (= 1 generic-confirmations))
    (should (equal moved '((1 "/quasimorphic/Trash" "-N"))))))

(ert-deftest afm/delete-installation-is-idempotent ()
  (afm/mu4e-install-safe-delete)
  (afm/mu4e-install-safe-delete)
  (afm/test-with-marks '((1 :docid 1 :maildir "/quasimorphic/Trash")) '((1 delete))
    (setq allow-delete t)
    (mu4e-mark-execute-all t)
    (should (equal removed '(1)))
    (should (= 1 confirmations))))

(ert-deftest afm/delete-view-buffer-uses-same-protection ()
  (afm/test-with-marks '((1 :docid 1 :maildir "/quasimorphic/Trash")) '((1 delete))
    (with-temp-buffer
      (setq major-mode 'mu4e-view-mode)
      (should-error (mu4e-mark-execute-all t) :type 'user-error))
    (should (= 1 confirmations))
    (should-not removed)))

;;; mu4e-safe-delete-tests.el ends here
