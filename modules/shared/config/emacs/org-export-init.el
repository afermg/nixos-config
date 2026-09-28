;; -*- lexical-binding: t -*-
(with-eval-after-load 'ox
  ;; Let explicit CUSTOM_ID and NAME values win in the LaTeX backend.
  (setq org-latex-prefer-user-labels t)

  (defun afm/org-export--title-reference-backend-p (info)
    "Return non-nil when INFO uses a title-reference export backend."
    (let ((backend (plist-get info :back-end)))
      (and backend
           (org-export-derived-backend-p backend 'html 'md 'latex))))

  (defun afm/org-export--reference-slug (title)
    "Convert headline TITLE to a portable HTML, Markdown, and LaTeX slug."
    (let ((slug (downcase (substring-no-properties title))))
      (setq slug (replace-regexp-in-string "[^[:alnum:]]+" "-" slug))
      (setq slug (replace-regexp-in-string "\\`-+\\|-+\\'" "" slug))
      (if (string-empty-p slug) "section" slug)))

  (defun afm/org-export--new-title-reference (datum cache)
    "Return a title-derived reference for DATUM that is unique in CACHE."
    (let* ((reference
            (afm/org-export--reference-slug
             (org-element-property :raw-value datum)))
           (parent (org-element-property :parent datum)))
      ;; Prefer an ancestor-qualified reference when duplicate titles occur.
      (while (and (assoc reference cache)
                  (eq (org-element-type parent) 'headline))
        (setq reference
              (concat
               (afm/org-export--reference-slug
                (org-element-property :raw-value parent))
               "--" reference)
              parent (org-element-property :parent parent)))
      ;; Identical outline paths receive a stable numeric suffix.
      (let ((base reference)
            (suffix 2))
        (while (assoc reference cache)
          (setq reference (format "%s--%d" base suffix)
                suffix (1+ suffix))))
      reference))

  (defun afm/org-export--get-title-reference (datum info)
    "Return and cache a unique title-derived reference for DATUM."
    (let ((cache (plist-get info :internal-references)))
      (or (car (rassq datum cache))
          (let* ((reference
                  (afm/org-export--new-title-reference datum cache))
                 (cells (org-export-search-cells datum)))
            (dolist (cell cells)
              (push (cons cell reference) cache))
            (push (cons reference datum) cache)
            (plist-put info :internal-references cache)
            reference))))

  (defun afm/org-export-get-reference (original datum info)
    "Use headline titles for HTML, Markdown, and LaTeX references."
    (if (and (eq (org-element-type datum) 'headline)
             (not (org-element-property :CUSTOM_ID datum))
             (afm/org-export--title-reference-backend-p info))
        (afm/org-export--get-title-reference datum info)
      (funcall original datum info)))

  (advice-remove 'org-export-get-reference
                 #'afm/org-export-get-reference)
  (advice-add 'org-export-get-reference :around
              #'afm/org-export-get-reference))

(use-package org-contrib
:config
(require 'ox-extra)
(ox-extras-activate '(ignore-headlines)))

(use-package ox-hugo
  :ensure t   ;Auto-install the package from Melpa
  :pin melpa  ;`package-archives' should already have ("melpa" . "https://melpa.org/packages/")
  :after org
  )

(defun org/parse-headings (backend)
  (if (member backend '(latex))
      (org-map-entries
       (lambda ()
         (progn
           (insert-string "#+LATEX: \\newpage")))

       "+newpage")))

(add-hook 'org-export-before-parsing-hook 'org/parse-headings)

(setq org-latex-default-class "extarticle")

(setq org-latex-prefer-user-labels t
         org-latex-caption-above nil
         ;; org-latex-listings 'minted
         org-latex-listings nil
         )


   ;;Colours
(add-to-list 'org-latex-packages-alist '("" "minted" nil))
(setq org-latex-minted-options nil)
      ;; '(
      ;; 				 ("frame" "leftline")
      ;; 				 ("lineos" "true")
      ;; 				 ))
(setq org-latex-src-block-backend 'minted)
 ;; (add-to-list 'org-latex-packages-alist '("" "minted"))
 ;(add-to-list 'org-latex-packages-alist '("" "tabularx"))
 ;(plist-put org-format-latex-options :scale 1.75        )
 ;(add-to-list 'org-latex-packages-alist '("" "unicode-math")))
  (add-to-list 'org-latex-classes
        '("beamerposter"
          "\\documentclass[final]{beamer}
          \\usepackage[T1]{fontenc}
          \\usepackage{lmodern}
          \\usepackage[size=custom,width=84.1,height=118.9,scale=1.0]{beamerposter}
          \\usepackage{graphicx}
          \\usepackage{booktabs}
          \\usepackage{tikz}
          \\usepackage{pgfplots}
          \\pgfplotsset{compat=1.18}
          \\usepackage{anyfontsize}
          [NO-DEFAULT-PACKAGES]"))
(add-to-list 'org-latex-classes
        '("extarticle"
                "\\documentclass{extarticle}"
                ("\\section{%s}" . "\\section*{%s}")
                ("\\subsection{%s}" . "\\subsection*{%s}")
                ("\\subsubsection{%s}" . "\\subsubsection*{%s}")))
(add-to-list 'org-latex-classes
        '("article-minimal"
                "\\documentclass{article}
                 [NO-DEFAULT-PACKAGES]"
                ("\\section{%s}" . "\\subsection*{%s}")
                ("\\subsection{%s}" . "\\subsubsection*{%s}")
                ("\\subsubsection{%s}" . "\\subsubsubsection*{%s}")))

(setq org-latex-compiler "xelatex")

;; Custom latex->PDF conversion
  ;; (setq org-latex-pdf-process
  ;;       '("latexmk -pdflatex='pdflatex -interaction nonstopmode' -shell-escape -pdf -bibtex --synctex=1 -f %f"))
  ;; (setq org-latex-pdf-process
  ;;       '("latexmk -pdflatex='lualatex -interaction nonstopmode' -shell-escape -pdf -bibtex --synctex=1 -f %f"))
  (setq latex-run-command "xelatex")
  (setq org-latex-pdf-process
        '("latexmk -pdflatex='xelatex -shell-escape -interaction nonstopmode ' -shell-escape -pdf -f %f "
          ;; "makeglossaries %
          ;; "biber %b"
          ;; "makeindex %b"
          "latexmk -pdflatex='xelatex -interaction -shell-escape nonstopmode ' -shell-escape -pdf -f %f "
          "latexmk -pdflatex='xelatex -shell-escape -interaction nonstopmode ' -shell-escape -pdf -f %f "))
