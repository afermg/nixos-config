;;; forge-tests.el --- Forge configuration regressions -*- lexical-binding: t; -*-

;; No packages, credentials, processes, or live Emacs sessions are accessed.
;; emacs --batch -Q -l modules/shared/config/emacs/tests/forge-tests.el \
;;   -f ert-run-tests-batch-and-exit
(require 'ert)
(require 'cl-lib)
(require 'subr-x)

(defvar afm/test-forge-form
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "../config.org" (file-name-directory load-file-name)))
    (search-forward "(use-package forge\n")
    (goto-char (match-beginning 0))
    (read (current-buffer))))

(defvar afm/test-pr-review-form
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "../config.org" (file-name-directory load-file-name)))
    (search-forward "(use-package pr-review\n")
    (goto-char (match-beginning 0))
    (read (current-buffer))))

(ert-deftest afm/pr-review-disables-source-syntax-highlighting ()
  (should (equal (plist-get (cddr afm/test-pr-review-form) :custom)
                 '(pr-review-diff-font-lock-syntax nil)))
  ;; Keep review lazy while applying the supported rendering option.
  (should (equal (plist-get (cddr afm/test-pr-review-form) :commands)
                 '(pr-review))))

(dolist (name '(afm/forge-ghub-token-from-gh afm/forge-pr-review))
  (let ((definition (cl-find-if
                     (lambda (form)
                       (and (consp form) (eq (car form) 'defun)
                            (eq (cadr form) name)))
                     (cddr afm/test-forge-form))))
    (unless definition (error "Missing Forge definition: %s" name))
    (eval definition t)))

(defmacro afm/test-forge-with-cli (available result output &rest body)
  "Stub CLI availability, RESULT and OUTPUT; record calls in `calls'."
  (declare (indent 3))
  `(let (calls)
     (cl-letf (((symbol-function 'executable-find)
                (lambda (name)
                  (should (equal name "gh"))
                  ,available))
               ((symbol-function 'call-process)
                (lambda (&rest args)
                  (push args calls)
                  (insert ,output)
                  ,result)))
       ,@body)))

(ert-deftest afm/forge-gh-account-specific-token ()
  (dolist (package '(forge emacs-pr-review))
    (dolist (forge '(nil github))
      (dolist (nocreate '(nil t))
        (afm/test-forge-with-cli "/stub/gh" 0 "  fake-test-token\n"
          (let (original-calls)
            (should
             (equal (afm/forge-ghub-token-from-gh
                     (lambda (&rest args) (push args original-calls) nil)
                     "api.github.com" "test-account" package nocreate forge)
                    "fake-test-token"))
            (should (equal original-calls
                           (list (list "api.github.com" "test-account" package t forge))))
            (should (equal calls
                           '(("/stub/gh" nil (t nil) nil "auth" "token"
                              "--hostname" "github.com" "--user" "test-account"))))))))))

(ert-deftest afm/forge-auth-source-precedes-cli ()
  (cl-letf (((symbol-function 'executable-find)
             (lambda (&rest _) (ert-fail "CLI lookup despite existing token")))
            ((symbol-function 'call-process)
             (lambda (&rest _) (ert-fail "CLI call despite existing token"))))
    (dolist (package '(forge emacs-pr-review))
      (should (equal (afm/forge-ghub-token-from-gh
                      (lambda (&rest _) "fake-existing-token")
                      "api.github.com" "test-account" package nil 'github)
                     "fake-existing-token")))))

(ert-deftest afm/forge-gh-exact-scope ()
  (cl-letf (((symbol-function 'executable-find)
             (lambda (&rest _) (ert-fail "CLI lookup outside scope")))
            ((symbol-function 'call-process)
             (lambda (&rest _) (ert-fail "CLI call outside scope"))))
    (dolist (args '(("github.com" "test-account" forge nil github)
                    ("api.github.com.enterprise" "test-account" forge t github)
                    ("gitlab.com" "test-account" forge nil gitlab)
                    ("api.github.com" "test-account" ghub nil github)
                    ("api.github.com" "test-account" pr-review nil github)
                    ("api.github.com" "test-account" other-package nil github)
                    ("github.com" "test-account" emacs-pr-review nil github)
                    ("api.github.com" "test-account" emacs-pr-review nil gitlab)
                    ("api.github.com" nil emacs-pr-review nil github)
                    ("api.github.com" "test-account" forge nil gitlab)
                    ("api.github.com" nil forge nil github)
                    ("api.github.com" test-account forge nil github)))
      (let (original-calls)
        (should (equal (apply #'afm/forge-ghub-token-from-gh
                              (lambda (&rest original-args)
                                (push original-args original-calls)
                                'original-result)
                              args)
                       'original-result))
        (should (equal original-calls (list args)))))))

(ert-deftest afm/forge-gh-failures-preserve-nocreate-and-errors ()
  (dolist (scenario '((nil 0 "fake-test-token")
                      ("/stub/gh" 1 "fake-test-token")
                      ("/stub/gh" "terminated" "fake-test-token")
                      ("/stub/gh" 0 " \n\t")
                      ("/stub/gh" 0 "")))
    (dolist (nocreate '(nil t))
      (afm/test-forge-with-cli (nth 0 scenario) (nth 1 scenario) (nth 2 scenario)
        (let* (original-calls
               (orig (lambda (host user package no-create forge)
                       (push (list host user package no-create forge) original-calls)
                       (unless no-create (error "Original missing-token error"))))
               (invoke (lambda ()
                         (afm/forge-ghub-token-from-gh
                          orig "api.github.com" "test-account" 'forge nocreate 'github))))
          (if nocreate
              (should-not (funcall invoke))
            (should (equal (should-error (funcall invoke))
                           '(error "Original missing-token error"))))
          (should (equal (nreverse original-calls)
                         (list '("api.github.com" "test-account" forge t github)
                               (list "api.github.com" "test-account" 'forge nocreate 'github))))
          (should (= (length calls) (if (car scenario) 1 0))))))))

(ert-deftest afm/forge-gh-process-error-preserves-original-behavior ()
  (cl-letf (((symbol-function 'executable-find) (lambda (_) "/stub/gh"))
            ((symbol-function 'call-process)
             (lambda (&rest _) (signal 'file-error '("Synthetic launch failure")))))
    (dolist (nocreate '(nil t))
      (let ((invoke (lambda ()
                      (afm/forge-ghub-token-from-gh
                       (lambda (_host _user _package no-create _forge)
                         (unless no-create (error "Original error")))
                       "api.github.com" "test-account" 'forge nocreate nil))))
        (if nocreate
            (should-not (funcall invoke))
          (should (equal (should-error (funcall invoke)) '(error "Original error"))))))))

(ert-deftest afm/forge-named-advice-is-idempotent ()
  (cl-letf (((symbol-function 'ghub--token) (lambda (&rest _) nil)))
    (unwind-protect
        (progn
          (dotimes (_ 2)
            (eval (cl-find-if (lambda (form)
                               (and (consp form) (eq (car form) 'advice-add)))
                             (cddr afm/test-forge-form)) t))
          (let ((count 0))
            (advice-mapc (lambda (fn _props)
                           (when (eq fn 'afm/forge-ghub-token-from-gh)
                             (cl-incf count)))
                         'ghub--token)
            (should (= count 1))))
      (advice-remove 'ghub--token #'afm/forge-ghub-token-from-gh))))

(ert-deftest afm/forge-pr-review-hands-off-current-pr-url ()
  ;; Forge's current-topic API covers both list selection and visited topics.
  (dolist (topic '(selected-pullreq visited-pullreq))
    (let (opened)
      (cl-letf (((symbol-function 'forge-current-topic) (lambda () topic))
                ((symbol-function 'forge-pullreq-p) (lambda (value) (eq value topic)))
                ((symbol-function 'forge-get-url)
                 (lambda (value)
                   (should (eq value topic))
                   "https://github.com/example/project/pull/123"))
                ((symbol-function 'pr-review) (lambda (url) (push url opened)))
                ((symbol-function 'read-string)
                 (lambda (&rest _) (ert-fail "Unexpected URL prompt"))))
        (call-interactively #'afm/forge-pr-review)
        (should (equal opened '("https://github.com/example/project/pull/123")))))))

(ert-deftest afm/forge-pr-review-rejects-non-pr-topics ()
  (dolist (topic '(nil issue discussion))
    (cl-letf (((symbol-function 'forge-current-topic) (lambda () topic))
              ((symbol-function 'forge-pullreq-p) (lambda (_) nil))
              ((symbol-function 'forge-get-url)
               (lambda (&rest _) (ert-fail "URL lookup for non-PR")))
              ((symbol-function 'pr-review)
               (lambda (&rest _) (ert-fail "Review opened for non-PR"))))
      (should-error (call-interactively #'afm/forge-pr-review) :type 'user-error))))

(ert-deftest afm/forge-menu-additions-are-idempotent-and-nonconflicting ()
  (let ((forms (cl-remove-if-not
                (lambda (form) (and (consp form) (eq (car form) 'unless)))
                (cdr (memq :config afm/test-forge-form)))))
    (should (= (length forms) 2))
    (dolist (preexisting '(nil t))
      (let ((suffixes (when preexisting '(("r r" . existing-command)))) calls)
        (cl-letf (((symbol-function 'transient-get-suffix)
                   (lambda (prefix key)
                     (should (eq prefix 'forge-dispatch))
                     (or (assoc key suffixes) (error "Missing suffix"))))
                  ((symbol-function 'transient-append-suffix)
                   (lambda (prefix anchor suffix)
                     (push (list prefix anchor suffix) calls)
                     (push (cons (car suffix) (nth 2 suffix)) suffixes))))
          (dotimes (_ 2) (dolist (form forms) (eval form t)))
          (should (= (length calls) (if preexisting 1 2)))
          (should (eq (cdr (assoc "l p" suffixes)) 'forge-list-pullreqs))
          (should (eq (cdr (assoc "r r" suffixes))
                      (if preexisting 'existing-command 'afm/forge-pr-review)))
          (should (member '(forge-dispatch "l t"
                            ("l p" "pull-requests" forge-list-pullreqs)) calls))
          (unless preexisting
            (should (member '(forge-dispatch "v p"
                              ("r r" "inline review" afm/forge-pr-review)) calls))))))))

;;; forge-tests.el ends here
