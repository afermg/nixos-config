;;; mu4e-sync-command-tests.el --- Mail sync shell regression tests -*- lexical-binding: t; -*-

;; emacs --batch -Q -l modules/shared/config/emacs/tests/mu4e-sync-command-tests.el \
;;   -f ert-run-tests-batch-and-exit
;; No user init, credentials, mail servers, or real sync programs are used.

(require 'ert)
(require 'cl-lib)

(defvar mu4e-get-mail-command)
(defconst afm/test-mail-sync-command
  (let ((config (expand-file-name "../config.org" (file-name-directory load-file-name)))
        (mu4e-get-mail-command nil))
    (with-temp-buffer
      (insert-file-contents config)
      (search-forward "(setq mu4e-get-mail-command")
      (goto-char (match-beginning 0))
      (eval (read (current-buffer)) t))
    mu4e-get-mail-command))

(defun afm/test-mail-sync-run (shell pull-status mirror-status archive-status)
  "Run the configured command under SHELL, using only isolated fake programs."
  (let* ((root (make-temp-file "mu4e sync test " t))
         (default-directory (file-name-as-directory root))
         (bin (expand-file-name "bin" root))
         (mirror (expand-file-name ".local/bin/mirror-mail" root))
         (trace (expand-file-name "trace" root))
         (process-environment (copy-sequence process-environment))
         (bash (or (executable-find "bash") (error "Bash is required"))))
    (unwind-protect
        (progn
          (make-directory bin t)
          (make-directory (file-name-directory mirror) t)
          (with-temp-file (expand-file-name "mbsync" bin)
            (insert "#!" bash "\n"
                    "if [ \"$*\" = '-a' ]; then\n"
                    "  echo pull >> \"$TEST_SYNC_TRACE\"\n"
                    "  exit \"$TEST_PULL_STATUS\"\n"
                    "elif [ \"$*\" = 'quasimorphic-archives quasimorphic:Junk' ]; then\n"
                    "  echo archives >> \"$TEST_SYNC_TRACE\"\n"
                    "  exit \"$TEST_ARCHIVE_STATUS\"\n"
                    "else exit 99; fi\n"))
          (with-temp-file mirror
            (insert "#!" bash "\n"
                    "[ \"$*\" = 'purdue broad broad-spam' ] || exit 99\n"
                    "echo mirror >> \"$TEST_SYNC_TRACE\"\n"
                    "exit \"$TEST_MIRROR_STATUS\"\n"))
          (set-file-modes (expand-file-name "mbsync" bin) #o700)
          (set-file-modes mirror #o700)
          (setenv "HOME" root)
          (setenv "PATH" (concat bin path-separator (getenv "PATH")))
          (setenv "BASH_ENV" nil)
          (setenv "TEST_SYNC_TRACE" trace)
          (setenv "TEST_PULL_STATUS" (number-to-string pull-status))
          (setenv "TEST_MIRROR_STATUS" (number-to-string mirror-status))
          (setenv "TEST_ARCHIVE_STATUS" (number-to-string archive-status))
          (with-temp-buffer
            (let ((status (apply #'call-process shell nil t nil
                                 (append (when (equal (file-name-nondirectory shell) "fish")
                                           '("--no-config"))
                                         (list "-c" afm/test-mail-sync-command)))))
              (list :status status :output (buffer-string)
                    :steps (when (file-exists-p trace)
                             (with-temp-buffer
                               (insert-file-contents trace)
                               (split-string (buffer-string) "\n" t)))))))
      (delete-directory root t))))

(ert-deftest afm/mail-sync-works-under-fish-and-bash ()
  (dolist (shell '("fish" "bash"))
    (let* ((program (or (executable-find shell) (ert-skip (concat "Missing " shell))))
           (result (afm/test-mail-sync-run program 0 0 0)))
      (should (equal (plist-get result :status) 0))
      (should (equal (plist-get result :steps) '("pull" "mirror" "archives"))))))

(ert-deftest afm/mail-sync-failed-source-prevents-import ()
  (dolist (shell '("fish" "bash"))
    (let ((result (afm/test-mail-sync-run
                   (or (executable-find shell) (ert-skip (concat "Missing " shell)))
                   7 0 0)))
      (should (equal (plist-get result :status) 7))
      (should (equal (plist-get result :steps) '("pull"))))))

(ert-deftest afm/mail-sync-import-failure-still-downloads-successful-imports ()
  (dolist (shell '("fish" "bash"))
    (let ((result (afm/test-mail-sync-run
                   (or (executable-find shell) (ert-skip (concat "Missing " shell)))
                   0 8 0)))
      (should (equal (plist-get result :status) 1))
      (should (equal (plist-get result :steps) '("pull" "mirror" "archives"))))))

(ert-deftest afm/mail-sync-archive-failure-is-not-masked ()
  (dolist (shell '("fish" "bash"))
    (let ((result (afm/test-mail-sync-run
                   (or (executable-find shell) (ert-skip (concat "Missing " shell)))
                   0 0 9)))
      (should (equal (plist-get result :status) 1))
      (should (equal (plist-get result :steps) '("pull" "mirror" "archives"))))))

(provide 'mu4e-sync-command-tests)
;;; mu4e-sync-command-tests.el ends here
