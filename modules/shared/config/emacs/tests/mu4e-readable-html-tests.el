;;; mu4e-readable-html-tests.el --- Theme-safe mail rendering -*- lexical-binding: t; -*-

;; Run without user init, reading mail, or accessing the network:
;; emacs --batch -Q -L /path/to/matching/mu4e \
;;   -l modules/shared/config/emacs/tests/mu4e-readable-html-tests.el \
;;   -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'mu4e)
(require 'shr)
(require 'eww)

(let ((config (expand-file-name "../config.org" (file-name-directory load-file-name)))
      (loaded 0))
  (with-temp-buffer
    (insert-file-contents config)
    (search-forward "(use-package mu4e\n")
    (goto-char (match-beginning 0))
    (dolist (form (cddr (read (current-buffer))))
      (when (or (and (eq (car-safe form) 'defun)
                     (eq (cadr form) 'afm/mu4e-theme-html))
                (equal form '(advice-add 'shr-insert-document :around
                                         #'afm/mu4e-theme-html)))
        (eval form t)
        (cl-incf loaded))))
  (unless (= loaded 2) (error "Missing mu4e HTML rendering definition/advice")))

(defconst afm/test-mail-html
  (concat "<html><body bgcolor=\"#909090\" text=\"#ffffff\">"
          "<p style=\"color:#222222;background-color:#111111\">"
          "Body <b>strong</b> <i>emphasis</i> "
          "<a href=\"https://example.invalid/\">read more</a></p>"
          "<table><tr><td bgcolor=\"#333333\">"
          "<span style=\"color:#222222\">Cell text</span></td>"
          "<td><table><tr><td bgcolor=\"#444444\">"
          "<font color=\"#333333\">Nested text</font>"
          "</td></tr></table></td></tr></table></body></html>"))

(defun afm/test-html-document ()
  "Parse fresh HTML; SHR annotates its DOM with rendering caches."
  (with-temp-buffer
    (insert afm/test-mail-html)
    (libxml-parse-html-region (point-min) (point-max))))

(defun afm/test-html-inline-colors-p ()
  "Return non-nil if the buffer contains explicit foreground/background faces."
  (cl-loop for pos from (point-min) below (point-max)
           thereis (let ((face (flatten-tree (get-text-property pos 'face))))
                     (or (memq :foreground face) (memq :background face)))))

(defmacro afm/test-html-render (&rest body)
  "Exercise real SHR rendering with deterministic batch color support."
  (declare (indent 0))
  `(let ((shr-use-colors t)
         (shr-use-fonts nil)
         (shr-width 72)
         (shr-inhibit-images t)
         (inhibit-read-only t))
     ;; Batch Emacs has no color terminal.  Keep the actual renderer and
     ;; colorization machinery, but make color availability/conversion stable.
     (cl-letf (((symbol-function 'display-color-cells) (lambda (&optional _) 256))
               ((symbol-function 'shr-color-check)
                (lambda (fg bg &optional _) (list bg fg))))
       ,@body)))

(ert-deftest afm/mu4e-html-keeps-theme-links-emphasis-and-nested-tables ()
  (afm/test-html-render
    (with-temp-buffer
      (mu4e-view-mode)
      (shr-insert-document (afm/test-html-document))
      (should-not (afm/test-html-inline-colors-p))
      (dolist (text '("Body" "Cell text" "Nested text"))
        (goto-char (point-min))
        (should (search-forward text nil t)))
      (dolist (pair '(("strong" . bold) ("emphasis" . italic)
                      ("read more" . shr-link)))
        (goto-char (point-min))
        (search-forward (car pair))
        (should (memq (cdr pair)
                      (flatten-tree (get-text-property (match-beginning 0) 'face)))))
      (should (equal (get-text-property (match-beginning 0) 'shr-url)
                     "https://example.invalid/"))
      (should shr-use-colors)
      (should-not (local-variable-p 'shr-use-colors)))))

(ert-deftest afm/mu4e-mime-html-renderer-also-uses-theme-colors ()
  (afm/test-html-render
    (let ((handle (with-temp-buffer
                    (insert "MIME-Version: 1.0\nContent-Type: text/html; charset=utf-8\n\n"
                            afm/test-mail-html)
                    (mm-dissect-buffer t))))
      (unwind-protect
          (with-temp-buffer
            (mu4e-view-mode)
            (let ((mm-html-inhibit-images t))
              (mm-shr handle))
            (should-not (afm/test-html-inline-colors-p))
            (should (string-match-p "Nested text" (buffer-string))))
        (mm-destroy-parts handle)))))

(ert-deftest afm/non-mail-html-retains-sender-colors ()
  (afm/test-html-render
    (with-temp-buffer
      (eww-mode)
      (shr-insert-document (afm/test-html-document))
      (should (afm/test-html-inline-colors-p))
      (should shr-use-colors))))

(ert-deftest afm/mu4e-html-color-binding-unwinds-on-error ()
  (let ((shr-use-colors t))
    (with-temp-buffer
      (mu4e-view-mode)
      (should-error
       (afm/mu4e-theme-html
        (lambda (argument)
          (should (eq argument 'sentinel))
          (should-not shr-use-colors)
          (with-temp-buffer (should-not shr-use-colors))
          (error "Synthetic renderer failure"))
        'sentinel)
       :type 'error)
      (should shr-use-colors))
    (should shr-use-colors)))

;;; mu4e-readable-html-tests.el ends here
