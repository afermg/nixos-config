;;; init.el --- Shared editor configuration, ix runtime integration -*- lexical-binding: t; -*-

;; The personal configuration stays the single source of truth. Nix supplies
;; the native tools; Straight's architecture-independent sources are portable.
(require 'exec-path-from-shell)
(load (expand-file-name
       "~/.local/share/src/nixos-config/modules/shared/config/emacs/init.el")
      nil nil)

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

;; The stable marker/path also supports rolling back to the previous profile.
(when (file-exists-p
       (expand-file-name "~/.local/state/raspi4-deployment/mail-index-complete"))
  (mu4e t))
