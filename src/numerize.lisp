(cl:in-package #:cl-user)

(defpackage #:chronicity-numerizer
  (:use #:cl)
  (:export #:numerize))

(in-package #:chronicity-numerizer)

#.(cl-interpol:enable-interpol-syntax)

(defvar *direct-nums*
  '(("eleven" 11)
    ("twelve" 12)
    ("thirteen" 13)
    ("fourteen" 14)
    ("fifteen" 15)
    ("sixteen" 16)
    ("seventeen" 17)
    ("eighteen" 18)
    ("nineteen" 19)
    ("ninteen" 19)                      ; Common mis-spelling
    ("zero" 0)
    ("one" 1)
    ("two" 2)
    ("three" 3)
    (#?r"\bfour\b" 4)         ; So that it matches four but not fourty
    ("five" 5)
    (#?r"\bsix\b" 6)
    (#?r"\bseven\b" 7)
    (#?r"\beight\b" 8)
    (#?r"\bnine\b" 9)
    ("ten" 10)
    ; (#?r"\ba[\b^$]" 1) ; doesn't make sense for an 'a' at the end to be a 1
    ))

(defvar *ten-prefixes*
  '(("twenty" 20)
    ("thirty" 30)
    ("(fourty|forty)" 40)
    ("fifty" 50)
    ("sixty" 60)
    ("seventy" 70)
    ("eighty" 80)
    ("ninety" 90)))

(defvar *big-prefixes*
  '(("hundred" 100)
    ("thousand" 1000)
    ("million" 1000000)
    ("billion" 1000000000)
    ("trillion" 1000000000000)))

(defun numerize (string)
  ;; Some normalization
  (setf string (cl-ppcre:regex-replace #?r"\band\b" string ""))
  (let ((start 0)
        (diff 0))
    (loop
       (multiple-value-bind (start2 end2)
           (and (< start (length string))
                (detect-numeral-sequence string :start start))
         (unless start2
           (return))
         (let ((number (numerize-aux (subseq string start2 end2))))
           (when number
             (setf (values string diff)
                   (replace-numeral-sequence string start2 end2 number)))
           (setf start (- end2 diff)))))
    string))

(defun replace-numeral-sequence (string start end number)
  (let ((number-string (format nil "~A" number)))
    (values
     (concatenate 'string
                  (subseq string 0 start)
                  number-string
                  (subseq string end))
     (- (- end start) (length number-string)))))

(defun numerize-aux (string)
  (let ((tokens (reverse (cl-ppcre:split #?r"(\s|-)+" string))))
    (setf tokens (remove-if-not #'numeric-token-p tokens))
    (tokens-to-number tokens)))

(defvar *big-detector-regex*
  (let ((big-or (format nil "(~{~A~^|~})"
                        (mapcar #'first (append *direct-nums*
                                                *ten-prefixes*
                                                *big-prefixes*)))))
    #?r"${big-or}((\s|-)+${big-or})*"))

(defun detect-numeral-sequence (string &key (start 0))
  (cl-ppcre:scan *big-detector-regex* string :start start))

(defun tokens-to-number (tokens)
  (when (big-prefix-p (first (last tokens)))
    (setf tokens (append tokens (list "one"))))
  (let* ((sum 0)
         (multiplier 1)
         (tsum 0)
         (tokens* tokens))
    (loop
       (unless tokens* (return))
       (let ((token (first tokens*)))
         (cond
           ((and (big-prefix-p token)
                 (> (token-numeric-value token) multiplier))
            (incf sum (* tsum multiplier))
            (setf tsum 0
                  multiplier (token-numeric-value token)))
           ((big-prefix-p token)
            (let ((next-big-multiplier (or (position-if #'(lambda (x)
                                                            (> (token-numeric-value x) multiplier))
                                                        tokens*)
                                           (length tokens*))))
              (let ((new-sum (tokens-to-number (subseq tokens* 0 next-big-multiplier))))
                (incf tsum new-sum)
                (setf tokens* (nthcdr (1- next-big-multiplier) tokens*)))))
           (t (incf tsum (token-numeric-value token)))))
       (setf tokens* (cdr tokens*)))
    (incf sum (* tsum multiplier))
    sum))

(defun numeric-token-p (string)
  (dolist (list (list *direct-nums* *ten-prefixes* *big-prefixes*))
    (dolist (numeral-pair list)
      (when (cl-ppcre:scan (first numeral-pair) string)
        (return-from numeric-token-p t)))))

(defun token-numeric-value (string)
  (dolist (list (list *direct-nums* *ten-prefixes* *big-prefixes*))
    (dolist (numeral-pair list)
      (when (cl-ppcre:scan (first numeral-pair) string)
        (return-from token-numeric-value (second numeral-pair))))))

(defun big-prefix-p (string)
  (dolist (numeral-pair *big-prefixes*)
    (when (cl-ppcre:scan (first numeral-pair) string)
      (return-from big-prefix-p t))))

(defun combine-adjacent-numbers (string)
  (let* ((bi-pairs (loop
                      for index = 0 then end
                      for (start end) = (multiple-value-list
                                         (cl-ppcre:scan #?/\b\d+(\s+\d+)*\b/ string
                                                        :start index))
                      while start
                      collect (list start end)))
         (number-strings (mapcar #'(lambda (x)
                                     (subseq string (first x) (second x)))
                                 bi-pairs))
         (numbers (mapcar #'compute-number number-strings)))
    (loop
       with result = string
       for (start end) in bi-pairs
       for number in numbers
       for str = (format nil "~A" number)
       for diff = (- (- end start) (length str))
       for fillbuf = (make-string diff :initial-element #\Null)
       for str2 = (concatenate 'string str fillbuf)
       while start
       do (setf result (replace result str2 :start1 start :end1 end))
       finally (return (cl-ppcre:regex-replace #?/\x0+/ result "")))))

(defun compute-number (string)
  (let ((index 0)
        (number nil))
    (loop
       do (setf (values number index)
                (parse-integer string
                               :start index
                               :junk-allowed t))
       while (and number (numberp index))
       collect number into numbers
       finally (return (compute-number-aux numbers)))))

(defun compute-number-aux (numbers)
  (cond
    ((null numbers) (error "Can't pass an empty list."))
    ((= (length numbers) 1) (first numbers))
    ((<= (first numbers) (second numbers))
     (compute-number-aux
      (cons (* (first numbers) (second numbers)) (cddr numbers))))
    ((every (lambda (n) (>= (first numbers) n)) (cdr numbers))
     (+ (first numbers) (compute-number-aux (cdr numbers))))
    (t
     (compute-number-aux
      (cons (+ (first numbers) (second numbers)) (cddr numbers))))))

;;; Disable cl-interpol reader

#.(cl-interpol:disable-interpol-syntax)









