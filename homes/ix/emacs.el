;;; init.el --- Shared editor configuration, ix runtime integration -*- lexical-binding: t; -*-

;; The personal configuration stays the single source of truth. Nix supplies
;; the native tools; Straight's architecture-independent sources are portable.
(require 'exec-path-from-shell)
(require 'seq)

;; The headless service loads Straight-managed packages from source. Avoid
;; native JIT compilation during daemon startup: it is noisy on new Emacs
;; releases and can push the systemd notify startup past its timeout.
(setq native-comp-jit-compilation nil
      native-comp-async-report-warnings-errors nil
      byte-compile-warnings '(not obsolete lexical free-vars unresolved
                                  noruntime cl-functions interactive-only))

;; The shared UI setup is also used by graphical profiles. In emacs-nox these
;; functions may be absent, so provide no-op definitions only for this host.
(dolist (fn '(scroll-bar-mode tool-bar-mode))
  (unless (fboundp fn)
    (defalias fn (lambda (&optional _arg) nil))))

(defvar ix--suppressed-startup-messages
  '("^Warning: Org source not found\\. Adding Org to package-archives\\.$")
  "Expected shared-startup messages suppressed for ix's headless daemon.")

(defun ix--message-filter (orig format-string &rest args)
  "Suppress known noisy ix daemon startup messages around shared init load."
  (let ((text (when (stringp format-string)
                (condition-case nil
                    (apply #'format-message format-string args)
                  (error format-string)))))
    (unless (and text
                 (seq-some (lambda (regexp) (string-match-p regexp text))
                           ix--suppressed-startup-messages))
      (apply orig format-string args))))

(advice-add 'message :around #'ix--message-filter)
(unwind-protect
    (load (expand-file-name
           "~/.local/share/src/nixos-config/modules/shared/config/emacs/init.el")
          nil nil)
  (advice-remove 'message #'ix--message-filter))

(require 'mu4e)
(unless (fboundp 'afm/mu4e-install-safe-delete)
  (error "The shared Emacs configuration did not finish loading"))

;; ix has scoped, private runtime credentials, not a cloned Bitwarden vault.
;; Keep the shared UI and mail safeguards, but do not prompt for a vault that
;; is not the credential provider here. Missing files still fail closed.
(defun ix-mail-credentials-locked-p ()
  "Check ix's unattended mail credentials without opening an unlock prompt."
  (dolist (file '("~/.config/raspi4-secrets/quasimorphic-password"
                  "~/.config/raspi4-secrets/broad-password"
                  "~/.local/state/oama/amunozgo@purdue.edu.oama"))
    (unless (file-readable-p (expand-file-name file))
      (user-error "ix mail credential is missing: %s" file)))
  nil)
(advice-add 'mu4e--rbw-locked-p :override #'ix-mail-credentials-locked-p)
(setq mu4e-get-mail-command "ix-mail-sync"
      mu4e-update-interval 300)
(afm/mu4e-install-safe-delete)

(defun ix-pi ()
  "Open Pi through the shared LLM dashboard."
  (interactive)
  (require 'llm-dashboard)
  (call-interactively #'llm-dashboard-new))

(defun ix-start-mu4e ()
  "Open mu4e after the daemon has reported readiness to systemd."
  (when (file-exists-p
         (expand-file-name "~/.local/state/raspi4-deployment/mail-index-complete"))
    (mu4e t)))

;; The stable marker/path also supports rolling back to the previous profile.
(if (daemonp)
    (run-at-time 10 nil #'ix-start-mu4e)
  (ix-start-mu4e))
