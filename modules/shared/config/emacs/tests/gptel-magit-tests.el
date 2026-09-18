;;; gptel-magit-tests.el --- OAuth commit-generation regressions -*- lexical-binding: t; -*-

;; No requests are sent: payload tests use gptel's dry-run mode.
;; Run with installed Straight dependencies on load-path, for example:
;; emacs --batch -Q --eval '(dolist (p (directory-files "~/.emacs.d/straight/build" t "^[^.]")) (when (file-directory-p p) (add-to-list (quote load-path) p)))' \
;;   -l modules/shared/config/emacs/tests/gptel-magit-tests.el \
;;   -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'gptel-magit)
(require 'gptel-openai-oauth)

(defvar afm/test-gptel-config-setup nil)

(let ((config (expand-file-name "../config.org" (file-name-directory load-file-name)))
      (names '(afm/gptel-magit--error-text afm/gptel-magit--collect-stream
               afm/gptel-magit--request afm/gptel-magit-install-oauth-compat))
      (loaded 0))
  (with-temp-buffer
    (insert-file-contents config)
    (search-forward "(defconst afm/gptel-openai-models")
    (goto-char (match-beginning 0))
    (eval (read (current-buffer)) t)
    (search-forward "(use-package gptel\n")
    (goto-char (match-beginning 0))
    (setq afm/test-gptel-config-setup
          (cl-find-if (lambda (form) (and (consp form) (eq (car form) 'setq)
                                        (memq 'gptel-backend form)))
                      (cddr (read (current-buffer)))))
    (unless afm/test-gptel-config-setup (error "Missing actual backend configuration"))
    (search-forward "(use-package gptel-magit\n")
    (goto-char (match-beginning 0))
    (dolist (form (cddr (read (current-buffer))))
      (when (and (consp form) (eq (car form) 'defun) (memq (cadr form) names))
        (eval form t)
        (cl-incf loaded))))
  (unless (= loaded (length names)) (error "Missing gptel-magit compatibility definitions")))
(afm/gptel-magit-install-oauth-compat)

(defmacro afm/test-gptel-oauth (&rest body)
  "Run BODY with isolated backend/model state and no credentials."
  (declare (indent 0))
  `(with-temp-buffer
     (let* ((gptel--known-backends nil)
            (gptel-backend (gptel-make-openai-oauth "test"
                             :models afm/gptel-openai-models
                             :header (lambda (&rest _) nil)))
            (gptel-model 'gpt-6-astra)
            (gptel-default-mode nil)
            (gptel-magit-model nil)
            (gptel-magit-backend nil)
            (gptel-temperature nil)
            (gptel-max-tokens nil)
            (gptel-use-tools nil)
            (gptel-tools nil)
            (gptel-include-reasoning nil))
       ,@body)))

(ert-deftest afm/gptel-registered-astra-is-the-model-on-the-wire ()
  (afm/test-gptel-oauth
    ;; Exercise the real saved backend constructor, not only this fixture.
    (eval afm/test-gptel-config-setup t)
    (let* ((fsm (gptel-magit--request "Synthetic diff"
                  :system "Write a commit message." :context nil :dry-run t
                  :callback #'ignore))
           (data (plist-get (gptel-fsm-info fsm) :data)))
      (should (equal (plist-get data :model) "gpt-6-astra"))
      (should (eq (plist-get data :stream) t))
      (should (eq (plist-get data :store) :json-false))
      (should (equal (plist-get data :instructions) "Write a commit message.")))))

(ert-deftest afm/gptel-stale-model-list-cannot-silently-fallback ()
  (afm/test-gptel-oauth
    (setf (gptel-backend-models gptel-backend) '(gpt-5.2))
    (let ((called nil))
      (should-error
       (afm/gptel-magit--request (lambda (&rest _) (setq called t))
                                "diff" :callback #'ignore)
       :type 'user-error)
      (should-not called)
      (should (eq gptel-model 'gpt-6-astra)))))

(ert-deftest afm/gptel-explicit-magit-model-is-respected ()
  (afm/test-gptel-oauth
    (let* ((gptel-magit-model 'gpt-5.4-mini)
           (fsm (gptel-magit--request "diff" :system "Commit" :dry-run t :callback #'ignore))
           (data (plist-get (gptel-fsm-info fsm) :data)))
      (should (equal (plist-get data :model) "gpt-5.4-mini")))))

(ert-deftest afm/gptel-known-string-model-is-accepted ()
  (afm/test-gptel-oauth
    (let ((gptel-magit-model "gpt-6-astra") (called nil))
      (afm/gptel-magit--request (lambda (&rest _) (setq called t))
                               "diff" :callback #'ignore)
      (should called))))

(ert-deftest afm/gptel-non-oauth-backend-passes-through-unchanged ()
  (afm/test-gptel-oauth
    (let* ((gptel-magit-backend (gptel-make-openai "other" :models '(other-model)))
           (args (list "diff" :callback #'ignore :stream nil))
           (result (apply #'afm/gptel-magit--request #'list args)))
      (should (equal result args)))))

(ert-deftest afm/gptel-stream-completes-once-without-reasoning ()
  (let (results)
    (let ((callback (afm/gptel-magit--collect-stream
                     (lambda (text _info) (push text results)))))
      (funcall callback "fix: " nil)
      (funcall callback '(reasoning . "Do not insert reasoning") nil)
      (funcall callback "Repair generation" nil)
      (should-not results)
      (funcall callback t '(:status "HTTP/2 200"))
      (funcall callback t '(:status "HTTP/2 200"))
      (funcall callback "late chunk" nil)
      (should (equal results '("fix: Repair generation"))))))

(ert-deftest afm/gptel-http-error-reports-cause-and-never-inserts-partial-text ()
  (let (results reports)
    (let ((callback (afm/gptel-magit--collect-stream
                     (lambda (text _info) (push text results)))))
      (cl-letf (((symbol-function 'message)
                 (lambda (&rest args) (push (apply #'format args) reports))))
        (funcall callback "partial" nil)
        (funcall callback nil '(:status "HTTP/2 400" :error "gpt-5.2 is not supported with a ChatGPT account"))
        (funcall callback t '(:status "HTTP/2 400")))
      (should-not results)
      (should (= (length reports) 1))
      (should (string-match-p "gpt-5.2 is not supported" (car reports))))))

(ert-deftest afm/gptel-stream-error-with-http-200-is-not-success ()
  (let (results)
    (let ((callback (afm/gptel-magit--collect-stream
                     (lambda (text _info) (push text results)))))
      (cl-letf (((symbol-function 'message) #'ignore))
        (funcall callback "partial" nil)
        (funcall callback t '(:status "HTTP/2 200" :error (:message "Stream failed"))))
      (should-not results))))

(ert-deftest afm/gptel-aborted-or-empty-response-does-not-invoke-package-callback ()
  (dolist (terminal '(abort t))
    (let (results)
      (let ((callback (afm/gptel-magit--collect-stream
                       (lambda (text _info) (push text results)))))
        (cl-letf (((symbol-function 'message) #'ignore))
          (funcall callback "  " nil)
          (funcall callback terminal nil)
          (funcall callback t nil))
        (should-not results)))))

(ert-deftest afm/gptel-error-report-does-not-dump-request-or-credentials ()
  (let ((text (afm/gptel-magit--error-text
               '(:status "HTTP/2 400"
                 :error (:message "Rejected Bearer dummy-credential and eyJdummy.payload.signature")
                 :data (:private "DO-NOT-LOG")))))
    (should (string-match-p "Rejected" text))
    (should-not (string-match-p "dummy-credential\\|eyJdummy\\|DO-NOT-LOG" text))))

(ert-deftest afm/gptel-adapter-replaces-old-advice-and-is-idempotent ()
  (advice-add 'gptel-magit--request :around
              (lambda (original &rest args) (apply original args))
              '((name . afm/openai-oauth-stream)))
  (afm/gptel-magit-install-oauth-compat)
  (afm/gptel-magit-install-oauth-compat)
  (should-not (advice-member-p 'afm/openai-oauth-stream 'gptel-magit--request))
  (let ((count 0))
    (advice-mapc (lambda (fn _props)
                  (when (eq fn #'afm/gptel-magit--request) (cl-incf count)))
                'gptel-magit--request)
    (should (= count 1))))

;;; gptel-magit-tests.el ends here
