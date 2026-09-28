;;; early-init.el --- ix headless daemon startup guards -*- lexical-binding: t; -*-

(setq native-comp-jit-compilation nil
      native-comp-async-report-warnings-errors nil
      byte-compile-warnings '(not obsolete lexical free-vars unresolved
                                  noruntime cl-functions interactive-only))

(require 'warnings)

(defvar ix--filter-startup-messages t
  "Whether ix should suppress expected headless daemon startup noise.")
(defvar ix--saved-warning-minimum-level warning-minimum-level)
(defvar ix--saved-warning-suppress-types warning-suppress-types)
(defvar ix--saved-warning-suppress-log-types warning-suppress-log-types)
(defvar ix--saved-enable-local-variables enable-local-variables)

(setq enable-local-variables nil
      warning-minimum-level :error
      warning-suppress-types '((files) (bytecomp) (comp))
      warning-suppress-log-types warning-suppress-types)

(defvar ix--suppressed-startup-messages
  '(
    "^Warning: Org source not found\\. Adding Org to package-archives\\.$"
    "^.*Warning (files): Missing .*lexical-binding.* cookie"
    "^You can add one with .*elisp-enable-lexical-binding"
    "^See .*Selecting Lisp Dialect.*"
    "^for more information\\.$"
    "^.*: Warning: .* is an obsolete .*"
    "Making lexical-binding buffer-local while locally let-bound!"
    )
  "Expected shared-startup messages suppressed for ix's headless daemon.")

(defun ix--message-filter (orig format-string &rest args)
  "Suppress known noisy ix daemon startup messages."
  (let ((text (when (stringp format-string)
                (condition-case nil
                    (apply #'format-message format-string args)
                  (error format-string)))))
    (unless (and ix--filter-startup-messages
                 text
                 (catch 'matched
                   (dolist (regexp ix--suppressed-startup-messages)
                     (when (string-match-p regexp text)
                       (throw 'matched t)))))
      (apply orig format-string args))))

(advice-add 'message :around #'ix--message-filter)
