;;; project-registration-tests.el --- Dashboard project persistence -*- lexical-binding: t; -*-

;; emacs --batch -Q -l modules/shared/config/emacs/tests/project-registration-tests.el \
;;   -f ert-run-tests-batch-and-exit
;; No user init, running agents, or real project registry is touched.

(require 'ert)
(require 'cl-lib)
(require 'project)

;; Exercise the real launch advice without starting a terminal or agent.
(defun llm-dashboard--launch (_cwd extra-args &optional _session-id)
  (if (eq (car extra-args) 'fail)
      (error "Synthetic launch failure")
    :launched))

(let ((config (expand-file-name "../config.org" (file-name-directory load-file-name))))
  (with-temp-buffer
    (insert-file-contents config)
    (search-forward "#+NAME: project-registration\n")
    (search-forward "#+BEGIN_SRC emacs-lisp\n")
    (let ((start (point))
          (end (progn (search-forward "#+END_SRC") (match-beginning 0))))
      (save-restriction
        (narrow-to-region start end)
        (goto-char (point-min))
        (while (progn (skip-chars-forward " \t\n") (not (eobp)))
          (eval (read (current-buffer)) t))))
    (search-forward "(defun afm/llm-dashboard-remember-project")
    (goto-char (match-beginning 0))
    (eval (read (current-buffer)) t)
    (eval (read (current-buffer)) t)))

(defmacro afm/test-project-registry (&rest body)
  "Run BODY with an isolated directory and persistent project registry."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "project-registry-" t)))
          (default-directory root)
          (project-list-file (expand-file-name "projects.eld" root))
          (project--list nil)
          (project-find-functions '(project-try-vc)))
     (unwind-protect
         (progn ,@body)
       (delete-directory root t))))

(ert-deftest afm/project-hooks-do-not-depend-on-magit ()
  (should-not (featurep 'magit))
  (should (memq #'afm/project-auto-remember find-file-hook))
  (should (memq #'afm/project-auto-remember dired-mode-hook)))

(ert-deftest afm/project-file-visit-remembers-repository-root ()
  (afm/test-project-registry
    (should (zerop (call-process "git" nil nil nil "init" "--quiet" root)))
    (let ((default-directory (expand-file-name "subdir/" root)))
      (make-directory default-directory)
      (with-temp-buffer
        (run-hooks 'find-file-hook)))
    (should (equal (project-known-project-roots) (list root)))
    (should (file-exists-p project-list-file))))

(ert-deftest afm/project-ordinary-directory-visits-are-not-projects ()
  (afm/test-project-registry
    (afm/project-auto-remember)
    (should-not (project-known-project-roots))
    (should-not (file-exists-p project-list-file))))

(ert-deftest afm/dashboard-launch-persists-non-vcs-directory-and-deduplicates ()
  (afm/test-project-registry
    (dotimes (_ 2)
      (should (eq (llm-dashboard--launch root nil "session-id") :launched)))
    (should (equal (project-known-project-roots) (list root)))
    ;; Reload from disk as a fresh Emacs would.
    (setq project--list 'unset)
    (should (equal (project-known-project-roots) (list root)))))

(ert-deftest afm/dashboard-failed-launch-does-not-register-directory ()
  (afm/test-project-registry
    (should-error (llm-dashboard--launch root '(fail)))
    (should-not (project-known-project-roots))
    (should-not (file-exists-p project-list-file))))

(ert-deftest afm/project-registration-does-not-probe-remote-directories ()
  ;; TRAMP's first load checks local cache directories; that is harmless.
  (require 'tramp)
  (cl-letf (((symbol-function 'file-directory-p)
             (lambda (&rest _) (ert-fail "Remote filesystem probe")))
            ((symbol-function 'project-current)
             (lambda (&rest _) (ert-fail "Remote project probe"))))
    (afm/project-auto-remember "/ssh:unreachable:/work/" t)))

(ert-deftest afm/project-registration-ignores-missing-directories ()
  (afm/test-project-registry
    (afm/project-auto-remember (expand-file-name "missing/" root) t)
    (should-not (project-known-project-roots))))

;;; project-registration-tests.el ends here
