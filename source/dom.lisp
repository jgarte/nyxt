;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(nyxt:define-package :nyxt/dom
  ;; FIXME: This is because window causes conflicts with buffer.lisp (somewhy?).
  (:shadow #:window)
  (:documentation "Nyxt-specific DOM classes and functions operating on them."))
(in-package :nyxt/dom)

;; TODO: Factor out into a library?

(defvar *nyxt-dom-classes* (make-hash-table :test #'equalp)
  "A table associating the HTML tag name (e.g., \"a\") with the corresponding
  nyxt/dom class.")

(defmacro define-element-classes (&body names)
  (loop for name in names
        collect (let* ((class-name (alex:ensure-car name))
                       (tag (str:replace-all "-element"  "" (str:downcase (symbol-name class-name))))
                       (additional-superclasses (when (listp name) (rest name))))
                  `(progn
                     (define-class ,class-name (,@(if additional-superclasses
                                                      additional-superclasses
                                                      '(plump:element)))
                       ()
                       (:export-class-name-p t)
                       (:export-accessor-names-p t)
                       (:export-predicate-name-p t)
                       (:accessor-name-transformer (class*:make-name-transformer name))
                       (:documentation ,(format nil "An autogenerated class for <~a> HTML tag." tag)))
                     (setf (gethash ,tag *nyxt-dom-classes*)
                           (quote ,class-name))))
          into classes
        finally (return `(progn ,@classes))))


(define-element-classes
  ;; All HTML5 tags, including experimental ones. Scraped with:
  ;;
  ;; (format t "~{~a-element~^ ~}"
  ;;         (map 'list #'(lambda (item)
  ;;                        (slot-value (elt (slot-value item 'plump-dom::%children) 0)
  ;;                                    'plump-dom::%text))
  ;;              (clss:select ".item-name" (plump:parse (dex:get "https://htmlreference.io/")))))
  ;; Pseudo-tags:
  text-element (h-element text-element) list-element structure-element semantic-element
  (checkbox-element input-element) (radio-element input-element) (file-chooser-element input-element)
  ;; HTML5 elements:
  (a-element text-element) abbr-element address-element area-element
  (article-element semantic-element) (aside-element semantic-element)
  audio-element (b-element text-element) base-element bdi-element bdo-element
  blockquote-element body-element br-element button-element canvas-element
  caption-element (cite-element text-element) (code-element text-element) col-element
  colgroup-element data-element datalist-element (dd-element list-element)
  (del-element text-element) details-element dfn-element div-element (dl-element list-element)
  (dt-element list-element) em-element embed-element fieldset-element
  (figcaption-element semantic-element) figure-element (footer-element semantic-element)
  form-element (h1-element h-element) (h2-element h-element) (h3-element h-element)
  (h4-element h-element) (h5-element h-element) (h6-element h-element) head-element
  (header-element semantic-element) hr-element html-element (i-element text-element) iframe-element
  img-element input-element ins-element kbd-element label-element legend-element
  (li-element list-element) link-element (main-element semantic-element) map-element
  (mark-element semantic-element) meta-element meter-element (nav-element semantic-element)
  noscript-element object-element (ol-element list-element) optgroup-element
  (option-element text-element) output-element (p-element text-element) param-element
  (pre-element text-element) progress-element q-element rp-element rt-element rtc-element
  ruby-element samp-element script-element (section-element semantic-element) select-element
  small-element source-element (span-element text-element) (strong-element text-element)
  style-element (sub-element text-element) summary-element (sup-element text-element) table-element
  tbody-element td-element textarea-element tfoot-element th-element thead-element
  (time-element semantic-element) title-element tr-element track-element (ul-element list-element)
  var-element video-element
  ;; obsolete elements (from https://www.w3.org/TR/2010/WD-html5-20100304/obsolete.html):
  applet-element acronym-element bgsound-element dir-element frame-element frameset-element
  noframes-element isindex-element (listing-element text-element) (xmp-element text-element)
  nextid-element noembed-element (plaintext-element text-element) (rb-element ruby-element)
  (basefont-element text-element) (big-element text-element) (blink-element text-element)
  (center-element text-element) (font-element text-element) (marquee-element text-element)
  (multicol-element text-element) (nobr-element text-element) (s-element text-element)
  (spacer-element text-element) (strike-element text-element) (tt-element text-element)
  (u-element text-element)
  ;; Experimental elements:
  dialog-element hgroup-element picture-element slot-element template-element
  (wbr-element text-element))

(defmethod name-dom-elements ((node plump:node))
  (alex:when-let* ((tag-p (plump:element-p node))
                   (class (gethash (plump:tag-name node) *nyxt-dom-classes*)))
    (change-class node class))
  (when (plump:nesting-node-p node)
    (loop for child across (plump:children node)
          do (name-dom-elements child)))
  node)

(export-always 'named-html-parse)
(-> named-parse (string) (values (or plump-dom:root null) &optional))
(defun named-html-parse (input)
  "Assign tag classes (e.g., `input-element') to the nodes in the `plump:parse'-d input."
  (name-dom-elements (plump:parse input)))

(define-parenscript get-document-body-json ()
  (defun process-element (element)
    (let ((object (ps:create :name (ps:@ element node-name)))
          (attributes (ps:chain element attributes)))
      (unless (or (ps:undefined attributes)
                  (= 0 (ps:@ attributes length)))
        (setf (ps:@ object :attributes) (ps:create))
        (loop for i from 0 below (ps:@ attributes length)
              do (setf (ps:@ object :attributes (ps:chain attributes (item i) name))
                       (ps:chain attributes (item i) value))))
      (unless (or (ps:undefined (ps:chain element child-nodes))
                  (= 0 (ps:chain element child-nodes length)))
        (setf (ps:chain object :children)
              (loop for child in (ps:chain element child-nodes)
                    collect (process-element child))))
      (when (or (equal (ps:@ element node-name) "#text")
                (equal (ps:@ element node-name) "#comment")
                (equal (ps:@ element node-name) "#cdata-section"))
        (setf (ps:@ object :text) (ps:@ element text-content)))
      object))
  (ps:chain -j-s-o-n (stringify (process-element (nyxt/ps:qs document "html")))))

(export-always 'named-json-parse)
(-> named-json-parse (string) (values (or plump-dom:root null) &optional))
(defun named-json-parse (json)
  "Return a `plump:root' of a DOM-tree produced from the JSON.

JSON should have the format like what `get-document-body-json' produces:
- A nested hierarchy of objects (with only one root object), where
  - Every object has a 'name' (usually a tag name or '#text'/'#comment').
  - Some objects can have 'attributes' (a string->string dictionary).
  - Some objects have a subarray ('children') of objects working by these three
    rules."
  (labels ((json-to-plump (json-hash parent)
             (let ((element
                     (cond
                       ((string-equal (gethash "name" json-hash) "#text")
                        (plump:make-text-node parent (gethash "text" json-hash)))
                       ((string-equal (gethash "name" json-hash) "#cdata-section")
                        (plump:make-cdata parent :text (gethash "text" json-hash)))
                       ((string-equal (gethash "name" json-hash) "#comment")
                        (plump:make-comment parent (gethash "text" json-hash)))
                       (t (plump:make-element parent (str:downcase
                                                      (gethash "name" json-hash)))))))
               (when (typep element 'plump:nesting-node)
                 (setf (plump:children element)
                       (plump:ensure-child-array
                        (map 'vector (rcurry #'json-to-plump element)
                             (let ((children (gethash "children" json-hash)))
                               (if (stringp children)
                                   (decode-json children)
                                   children))))))
               (when (typep element 'plump:element)
                 (setf (plump:attributes element)
                       (sera:lret ((map (plump:make-attribute-map)))
                         (when (gethash "attributes" json-hash)
                           (maphash (lambda (key val)
                                      (setf (gethash key map) val))
                                    (gethash "attributes" json-hash))))))
               element)))
    (let ((json (decode-json json))
          (root (plump:make-root)))
      (json-to-plump json root)
      (name-dom-elements root))))

(export-always 'parents)
(defgeneric parents (node)
  (:method ((node plump:node)) nil)
  (:method ((node plump:child-node))
    (let ((parent (plump:parent node)))
      (cons parent (parents parent))))
  (:documentation "Get the recursive parents of the NODE.
The closest parent goes first, the furthest one goes last."))

(export-always 'ordered-select)
(defun ordered-select (selector root)
  "A re-implementation of `clss:select' with the goal of preserving elements order.

SELECTOR is any selector acceptable to `clss', including the compiled one and
string one."
  (declare (optimize speed))
  (let ((matched-nodes (make-array 0 :adjustable t :fill-pointer 0))
        (selector (clss::ensure-selector selector)))
    (labels ((collect-if-match (element)
               (when (clss:node-matches-p selector element)
                 (vector-push-extend element matched-nodes))
               (map nil #'collect-if-match (plump:child-elements element))))
      (collect-if-match root)
      matched-nodes)))

(export-always 'get-nyxt-id)
(defmethod get-nyxt-id ((element plump:element))
  (plump:get-attribute element "nyxt-identifier"))

(export-always 'get-unique-selector)
(-> get-unique-selector (plump:element) t)
(defmemo get-unique-selector (element)
  "Find the shortest selector that uniquely identifies the element on a page.
Rely (in the order of importance) on:
- ID.
- Tag name.
- CSS Classes.
- Attributes.
- Parent and sibling node selectors (recursively).

If none of those provides the unique selector, return the most specific selector
calculated.

Return two values:
- The selector for the value.
- A boolean for whether this selector is unique (no other nodes matching it)."
  (let* ((tag-name (plump:tag-name element))
         (identifier (plump:get-attribute element "id"))
         (raw-classes (plump:get-attribute element "class"))
         ;; TODO: Remove other attributes, unreliable ones? For example, href
         ;; and type are reliable and are unlikely to change, while data-*
         ;; attributes are unreliable and can change any moment.
         (attributes (remove-if (rcurry #'member '("class" "id") :test #'string=)
                                (alex:hash-table-keys (plump:attributes element))))
         (classes (when raw-classes (remove-if #'str:blankp (str:split " " raw-classes))))
         (parents (parents element))
         (family (plump:family element))
         (previous (ignore-errors (plump:previous-element element)))
         ;; Is it guaranteed that the topmost ancestor of a node is
         ;; `plump:root'? Anyway, it should work even if there's a single
         ;; `plump:element' as a root.
         (root (alex:lastcar parents))
         (selector ""))
    (labels ((selconcat (&rest strings)
               (setf selector (sera:string-join (subst selector :sel strings) "")))
             (unique-p (selector)
               (sera:single (clss:select selector root)))
             (selreturn ()
               (return-from get-unique-selector (values selector (unique-p selector)))))
      ;; ID should be globally unique, so we check it first.
      (when (and identifier (sera:single (clss:select (selconcat :sel "#" identifier)  root)))
        (selreturn))
      ;; selconcat hack doesn't look nice here, but should work for cases of
      ;; both empty selector and ID selector.
      (when (unique-p (selconcat tag-name :sel))
        (selreturn))
      (when classes
        (mapc (lambda (class)
                (when (unique-p (selconcat :sel "." class))
                  (selreturn)))
              classes))
      (when attributes
        (mapc (lambda (attribute)
                (when (unique-p (selconcat :sel "[" attribute "=\""
                                            (plump:attribute element attribute) "\"]"))
                  (selreturn)))
              attributes))
      ;; Check for short and nice parent-child relations, like :only-child,
      ;; :last-child etc.
      ;;
      ;; FIXME: :nth-child would be extremely useful there, but it seems to by
      ;; unpredictable in CLSS (or CSS?).
      (when (and parents
                 (sera:single family)
                 (unique-p (selconcat :sel ":only-child")))
        (selreturn))
      (when (and parents
                 (not (sera:single family))
                 (eq element (elt family 0))
                 (unique-p (selconcat :sel ":first-child")))
        (selreturn))
      (when (and parents
                 (not (sera:single family))
                 (eq element (elt family (1- (length family))))
                 (unique-p (selconcat :sel ":last-child")))
        (selreturn))
      ;; Then check for previous siblings.
      (when (and previous
                 (unique-p (selconcat (get-unique-selector previous)  " ~ " :sel)))
        (selreturn))
      ;; Finally, go up the hierarchy.
      (when (and parents
                 (unique-p (selconcat (get-unique-selector (first parents)) " > " :sel)))
        (selreturn))
      (error "There's no unique selector for ~a, the best quess is ~s" element selector))))

(defmethod url :around ((element plump:element))
  (alex:when-let* ((result (call-next-method))
                   (url (nyxt::ensure-url result)))
    (if (valid-url-p url)
        url
        (quri:merge-uris url (url (current-buffer))))))

(defmethod url ((element plump:element))
  (when (plump:has-attribute element "href")
    (quri:uri (plump:get-attribute element "href"))))

(defmethod url ((img img-element))
  (when (plump:has-attribute img "src")
    (quri:uri (plump:get-attribute img "src"))))

(let ((text-memo-table (tg:make-weak-hash-table :weakness :key)))
  (defmethod plump:text :around ((node plump:nesting-node))
    (alex:ensure-gethash node text-memo-table (call-next-method))))

(export-always 'find-text)
(defmethod find-text ((text string) (element plump:nesting-node)
                      &key (test #'search))
  "Find all the matches for the TEXT in ELEMENT and its children.

TEST should be a function of two arguments comparing TEXT with element's
`plump:text' and returning a boolean for whether there's a match."
  (flet ((matches (elem)
           (find-text text elem :test test)))
    (when (funcall test text (plump:text element))
      (or (alex:mappend #'matches (coerce (plump:child-elements element) 'list))
          (list element)))))

;; REVIEW: Export to :nyxt? We are forced to use it with nyxt/dom: prefix.
(export-always 'body)
(defmethod body ((element plump:element))
  (when (plump:children element)
    (plump:text element)))

(defmethod body ((input input-element))
  (alex:when-let ((body (or (plump:get-attribute input "value")
                            (plump:get-attribute input "placeholder"))))
    body))

(defmethod body ((textarea textarea-element))
  (alex:when-let ((body (or (plump:get-attribute textarea "value")
                            (plump:get-attribute textarea "placeholder"))))
    body))

(defmethod body ((details details-element))
  (let ((summary (clss:select "summary" details)))
    (unless (uiop:emptyp summary)
      (plump:text (elt summary 0)))))

(defmethod body ((select select-element))
  (str:join ", " (map 'list #'plump:text
                      (clss:select "option" select))))

(defmethod body ((img img-element))
  (when (plump:has-attribute img "alt")
    (plump:get-attribute img "alt")))

(export-always 'click-element)
(define-parenscript click-element (element)
  (ps:chain (nyxt/ps:qs-nyxt-id document (ps:lisp (get-nyxt-id element))) (click)))

(export-always 'focus-select-element)
(define-parenscript focus-select-element (element)
  (let ((element (nyxt/ps:qs-nyxt-id document (ps:lisp (get-nyxt-id element)))))
    (ps:chain element (focus))
    (when (functionp (ps:chain element select))
      (ps:chain element (select)))))

(export-always 'check-element)
(define-parenscript check-element (element &key (value t))
  (ps:chain (nyxt/ps:qs-nyxt-id document (ps:lisp (get-nyxt-id element)))
            (set-attribute "checked" (ps:lisp value))))

(export-always 'toggle-details-element)
(define-parenscript toggle-details-element (element)
  (ps:let ((element (nyxt/ps:qs-nyxt-id document (ps:lisp (get-nyxt-id element)))))
    (if (ps:chain element (get-attribute "open"))
        (ps:chain element (remove-attribute "open"))
        (ps:chain element (set-attribute "open" t)))))

(export-always 'select-option-element)
(define-parenscript select-option-element (element parent)
  (ps:let* ((element (nyxt/ps:qs-nyxt-id document (ps:lisp (get-nyxt-id element))))
            (parent-select (nyxt/ps:qs-nyxt-id document (ps:lisp (get-nyxt-id parent)))))
    (if (ps:chain element (get-attribute "multiple"))
        (ps:chain element (set-attribute "selected" t))
        (setf (ps:@ parent-select value) (ps:@ element value)))))

(export-always 'hover-element)
(define-parenscript hover-element (element)
  (ps:let ((element (nyxt/ps:qs-nyxt-id document (ps:lisp (get-nyxt-id element))))
           (event (ps:new (*Event "mouseenter"))))
    (ps:chain element (dispatch-event event))))

(export-always 'scroll-to-element)
(define-parenscript scroll-to-element (element)
  (ps:chain (nyxt/ps:qs-nyxt-id document (ps:lisp (get-nyxt-id element)))
            (scroll-into-view t)))

(export-always 'set-caret-on-start)
(define-parenscript set-caret-on-start (element)
  (let ((el (nyxt/ps:qs-nyxt-id document (ps:lisp (get-nyxt-id element))))
        (range (ps:chain document (create-range)))
        (sel (ps:chain window (get-selection))))
    (ps:chain window (focus))
    (ps:chain range (set-start (ps:@ el child-nodes 0) 0))
    (ps:chain range (collapse true))
    (ps:chain sel (remove-all-ranges))
    (ps:chain sel (add-range range))))
