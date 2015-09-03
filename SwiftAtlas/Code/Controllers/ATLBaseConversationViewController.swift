import Foundation

class ATLBaseConversationViewController: UIViewController {
    /**
     @abstract The `ATLAddressBarViewController` displayed for addressing new conversations or displaying names of current conversation participants.
     */
    var addressBarController: ATLAddressBarViewController!

    /**
     @abstract The `ATLMessageInputToolbar` displayed for user input.
     */
    var messageInputToolbar: ATLMessageInputToolbar!

    /** 
     @abstract An `ATLTypingIndicatorViewController` displayed to represent participants typing in a conversation.
     */
    var typingIndicatorController: ATLTypingIndicatorViewController!

    /**
     @abstract The `UICollectionView` responsible for displaying messaging content. 
     @discussion Subclasses should set the collection view property in their `loadView` method. The controller will then handle configuring autolayout constraints for the collection view.
     */
    var _collectionView: UICollectionView?

    ///----------------------------------------------
    /// @name Configuring View Options
    ///----------------------------------------------

    /**
     @abstract A constant representing the current height of the typing indicator.
     */
    var _typingIndicatorInset: CGFloat = 0.0

    /**
     @abstract IA boolean value to determine whether or not the receiver should display an `ATLAddressBarController`. If yes, applications should implement `ATLAddressBarControllerDelegate` and `ATLAddressBarControllerDataSource`. Default is no.
     */
    var displaysAddressBar: Bool = false

    // http://stackoverflow.com/questions/24131627/swift-subclassing-a-uiviewcontrollers-root-view
    var myView: ATLConversationView { return self.view as! ATLConversationView }

    var typingParticipantIDs: NSMutableArray?
    var typingIndicatorViewBottomConstraint: NSLayoutConstraint = NSLayoutConstraint()
    var keyboardHeight: CGFloat = 0.0
    var firstAppearance: Bool = false
    
    var isFirstAppearance: Bool {
        get {
            return firstAppearance
        }
    }

    private let ATLTypingIndicatorHeight: CGFloat = 20
    private let ATLMaxScrollDistanceFromBottom: CGFloat = 150

    init() {
        super.init(nibName: nil, bundle: nil)
        baseCommonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        baseCommonInit()
    }

    func baseCommonInit() {
        displaysAddressBar = false
        typingParticipantIDs = NSMutableArray()
        firstAppearance = true
    }

    override func loadView() {
        self.view = ATLConversationView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add message input tool bar
        self.messageInputToolbar = ATLMessageInputToolbar()
        // An apparent system bug causes a view controller to not be deallocated
        // if the view controller's own inputAccessoryView property is used.
        self.myView.inputAccessoryView = self.messageInputToolbar
        
        // Add typing indicator
        self.typingIndicatorController = ATLTypingIndicatorViewController()
        self.addChildViewController(self.typingIndicatorController)
        self.myView.addSubview(self.typingIndicatorController.view)
        self.typingIndicatorController.didMoveToParentViewController(self)
        self.configureTypingIndicatorLayoutConstraints()
        
        // Add address bar if needed
        if self.displaysAddressBar {
            self.addressBarController = ATLAddressBarViewController()
            self.addChildViewController(self.addressBarController)
            self.myView.addSubview(self.addressBarController.view)
            self.addressBarController.didMoveToParentViewController(self)
            self.configureAddressbarLayoutConstraints()
        }
        self.atl_baseRegisterForNotifications()
        
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        // Workaround for a modal dismissal causing the message toolbar to remain offscreen on iOS 8.
        if self.presentedViewController != nil {
            self.myView.becomeFirstResponder()
        }
        if self.addressBarController != nil && self.firstAppearance {
            self.updateTopCollectionViewInset()
        }
        self.updateBottomCollectionViewInset()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // To get the toolbar to slide onscreen with the view controller's content, we have to make the view the
        // first responder here. Even so, it will not animate on iOS 8 the first time.
        if self.presentedViewController == nil && self.navigationController != nil && self.myView.inputAccessoryView.superview == nil {
            self.myView.becomeFirstResponder()
        }
        
        if self.isFirstAppearance {
            self.firstAppearance = false
            // We use the content size of the actual collection view when calculating the ammount to scroll. Hence, we layout the collection view before scrolling to the bottom.
            self.myView.layoutIfNeeded()
            self.scrollToBottomAnimated(false)
        }
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Workaround for view's content flashing onscreen after pop animation concludes on iOS 8.
        let isPopping: Bool = self.navigationController!.viewControllers.contains(self) == false
        if isPopping {
            self.messageInputToolbar!.textInputView.resignFirstResponder()
        }
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }

    // MARK:- Public Setters

    var collectionView: UICollectionView {
        get {
            return _collectionView!
        }
        
        set {
            _collectionView = newValue
            _collectionView!.translatesAutoresizingMaskIntoConstraints = false
            self.myView.addSubview(_collectionView!)
            self.configureCollectionViewLayoutConstraints()
        }
    }

    var typingIndicatorInset: CGFloat {
        get {
            return _typingIndicatorInset
        }
        
        set {
            _typingIndicatorInset = newValue
            UIView.animateWithDuration(0.1, animations: {
                self.updateBottomCollectionViewInset()
            })
        }
    }

    // MARK:- Public Methods

    /**
     @abstract Returns a boolean value to determines whether or not the controller should scroll the collection view content to the bottom.
     @discussion Returns NO if the content is further than 150px from the bottom of the collection view or the collection view is currently scrolling.
     */
    func shouldScrollToBottom() -> Bool {
        let bottomOffset: CGPoint = self.bottomOffsetForContentSize(self.collectionView.contentSize)
        let distanceToBottom: CGFloat = bottomOffset.y - self.collectionView.contentOffset.y
        let shouldScrollToBottom: Bool = distanceToBottom <= ATLMaxScrollDistanceFromBottom && !self.collectionView.tracking && !self.collectionView.dragging && !self.collectionView.decelerating
        return shouldScrollToBottom
    }

    /**
     @abstract Informs the controller that it should scroll the collection view to the bottom of its content. 
     @param animated A boolean value to determine whether or not the scroll should be animated. 
     */
    func scrollToBottomAnimated(animated: Bool) {
        let contentSize: CGSize = self.collectionView.contentSize
        self.collectionView.setContentOffset(self.bottomOffsetForContentSize(contentSize), animated: animated)
    }

    // MARK:- Content Inset Management

    func updateTopCollectionViewInset() {
        self.addressBarController.view.layoutIfNeeded()
        
        var contentInset: UIEdgeInsets = self.collectionView.contentInset
        var scrollIndicatorInsets: UIEdgeInsets = self.collectionView.scrollIndicatorInsets
        let frame: CGRect = self.view.convertRect(self.addressBarController.addressBarView.frame, fromView: self.addressBarController.addressBarView.superview)
        
        contentInset.top = CGRectGetMaxY(frame)
        scrollIndicatorInsets.top = contentInset.top
        self.collectionView.contentInset = contentInset
        self.collectionView.scrollIndicatorInsets = scrollIndicatorInsets
    }

    func updateBottomCollectionViewInset() {
        self.messageInputToolbar.layoutIfNeeded()
        
        var insets: UIEdgeInsets = self.collectionView.contentInset
        let keyboardHeight: CGFloat = max(self.keyboardHeight, CGRectGetHeight(self.messageInputToolbar.frame))
        
        insets.bottom = keyboardHeight + self.typingIndicatorInset
        self.collectionView.scrollIndicatorInsets = insets;
        self.collectionView.contentInset = insets;
        self.typingIndicatorViewBottomConstraint.constant = -keyboardHeight
    }

    // MARK:- Notification Handlers

    func keyboardWillShow(notification: NSNotification) {
        self.configureWithKeyboardNotification(notification)
    }

    func keyboardWillHide(notification: NSNotification) {
        if !self.navigationController!.viewControllers.contains(self) {
            return
        }
        self.configureWithKeyboardNotification(notification)
    }

    func messageInputToolbarDidChangeHeight(notification: NSNotification) {
        if self.messageInputToolbar.superview == nil {
           return
        }
        
        let toolbarFrame: CGRect = self.myView.convertRect(self.messageInputToolbar.frame, fromView: self.messageInputToolbar.superview)
        let keyboardOnscreenHeight: CGFloat = CGRectGetHeight(self.view.frame) - CGRectGetMinY(toolbarFrame)
        if keyboardOnscreenHeight == self.keyboardHeight {
            return
        }
        
        let messagebarDidGrow: Bool = keyboardOnscreenHeight > self.keyboardHeight
        self.keyboardHeight = keyboardOnscreenHeight
        self.typingIndicatorViewBottomConstraint.constant = -self.collectionView.scrollIndicatorInsets.bottom
        self.updateBottomCollectionViewInset()
        
        if self.shouldScrollToBottom() && messagebarDidGrow {
            self.scrollToBottomAnimated(true)
        }
    }

    func textViewTextDidBeginEditing(notification: NSNotification) {
        self.scrollToBottomAnimated(true)
    }

    // MARK:- Keyboard Management

    func configureWithKeyboardNotification(notification: NSNotification) {
        let keyboardBeginFrame: CGRect? = (notification.userInfo?[UIKeyboardFrameBeginUserInfoKey] as? NSValue)?.CGRectValue()
        let keyboardBeginFrameInView: CGRect  = self.myView.convertRect(keyboardBeginFrame!, fromView: nil)
        let keyboardEndFrame: CGRect? = (notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.CGRectValue()
        let keyboardEndFrameInView: CGRect = self.myView.convertRect(keyboardEndFrame!, fromView: nil)
        let keyboardEndFrameIntersectingView: CGRect = CGRectIntersection(self.view.bounds, keyboardEndFrameInView)
        
        var keyboardHeight: CGFloat = CGRectGetHeight(keyboardEndFrameIntersectingView)
        // Workaround for keyboard height inaccuracy on iOS 8.
        if floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_7_1 {
            keyboardHeight -= CGRectGetMinY(self.messageInputToolbar.frame)
        }
        self.keyboardHeight = keyboardHeight
        
        // Workaround for collection view cell sizes changing/animating when view is first pushed onscreen on iOS 8.
        if CGRectEqualToRect(keyboardBeginFrameInView, keyboardEndFrameInView) {
            UIView.performWithoutAnimation {
                self.updateBottomCollectionViewInset()
            }
            return
        }
        
        self.myView.layoutIfNeeded()
        UIView.beginAnimations(nil, context: nil)
        UIView.setAnimationDuration(((notification.userInfo?[UIKeyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue)!)
        let animationCurveInt = ((notification.userInfo?[UIKeyboardAnimationCurveUserInfoKey] as? NSNumber)?.integerValue)!
        UIView.setAnimationCurve(UIViewAnimationCurve(rawValue: animationCurveInt)!)
        UIView.setAnimationBeginsFromCurrentState(true)
        self.updateBottomCollectionViewInset()
        self.myView.layoutIfNeeded()
        UIView.commitAnimations()
    }

    // MARK:- Helpers

    /**
     @abstract Calculates the bottom offset of the collection view taking into account any current insets caused by `addressBarController`, `typingIndicatorViewController` or `messageInputToolbar`.
     */
    func bottomOffsetForContentSize(contentSize: CGSize) -> CGPoint {
        let contentSizeHeight: CGFloat = contentSize.height
        let collectionViewFrameHeight: CGFloat = self.collectionView.frame.size.height
        let collectionViewBottomInset: CGFloat = self.collectionView.contentInset.bottom
        let collectionViewTopInset: CGFloat = self.collectionView.contentInset.top
        let offset: CGPoint = CGPointMake(0, max(-collectionViewTopInset, contentSizeHeight - (collectionViewFrameHeight - collectionViewBottomInset)))
        return offset
    }

    override func updateViewConstraints() {
        var typingIndicatorBottomConstraintConstant: CGFloat = -self.collectionView.scrollIndicatorInsets.bottom
        if self.messageInputToolbar.superview != nil {
            let toolbarFrame: CGRect = self.myView.convertRect(self.messageInputToolbar.frame, fromView: self.messageInputToolbar.superview)
            let keyboardOnscreenHeight: CGFloat = CGRectGetHeight(self.view.frame) - CGRectGetMinY(toolbarFrame)
            if -keyboardOnscreenHeight > typingIndicatorBottomConstraintConstant {
                typingIndicatorBottomConstraintConstant = -keyboardOnscreenHeight
            }
        }
        self.typingIndicatorViewBottomConstraint.constant = typingIndicatorBottomConstraintConstant
        super.updateViewConstraints()
    }

    // MARK:- Auto Layout

    func configureCollectionViewLayoutConstraints() {
        self.myView.addConstraint(NSLayoutConstraint(item: self.collectionView, attribute: NSLayoutAttribute.Left, relatedBy: NSLayoutRelation.Equal, toItem: self.myView, attribute: NSLayoutAttribute.Left, multiplier: 1.0, constant: 0))
        self.myView.addConstraint(NSLayoutConstraint(item: self.collectionView, attribute: NSLayoutAttribute.Right, relatedBy: NSLayoutRelation.Equal, toItem: self.myView, attribute: NSLayoutAttribute.Right, multiplier: 1.0, constant: 0))
        self.myView.addConstraint(NSLayoutConstraint(item: self.collectionView, attribute: NSLayoutAttribute.Top, relatedBy: NSLayoutRelation.Equal, toItem: self.myView, attribute: NSLayoutAttribute.Top, multiplier: 1.0, constant: 0))
        self.myView.addConstraint(NSLayoutConstraint(item: self.collectionView, attribute: NSLayoutAttribute.Bottom, relatedBy: NSLayoutRelation.Equal, toItem: self.myView, attribute: NSLayoutAttribute.Bottom, multiplier: 1.0, constant: 0))
    }

    func configureTypingIndicatorLayoutConstraints() {
        // Typing Indicatr
        self.myView.addConstraint(NSLayoutConstraint(item: self.typingIndicatorController.view, attribute: NSLayoutAttribute.Left, relatedBy: NSLayoutRelation.Equal, toItem: self.myView, attribute: NSLayoutAttribute.Left, multiplier: 1.0, constant: 0))
        self.myView.addConstraint(NSLayoutConstraint(item: self.typingIndicatorController.view, attribute: NSLayoutAttribute.Width, relatedBy: NSLayoutRelation.Equal, toItem: self.myView, attribute: NSLayoutAttribute.Width, multiplier: 1.0, constant: 0))
        self.myView.addConstraint(NSLayoutConstraint(item: self.typingIndicatorController.view, attribute: NSLayoutAttribute.Height, relatedBy: NSLayoutRelation.Equal, toItem: nil, attribute: NSLayoutAttribute.NotAnAttribute, multiplier: 1.0, constant: ATLTypingIndicatorHeight))
        self.typingIndicatorViewBottomConstraint = NSLayoutConstraint(item: self.typingIndicatorController.view, attribute: NSLayoutAttribute.Bottom, relatedBy: NSLayoutRelation.Equal, toItem: self.myView, attribute: NSLayoutAttribute.Bottom, multiplier: 1.0, constant: 0)
        self.myView.addConstraint(self.typingIndicatorViewBottomConstraint)
    }

    func configureAddressbarLayoutConstraints() {
        // Address Bar
        self.myView.addConstraint(NSLayoutConstraint(item: self.addressBarController.view, attribute: NSLayoutAttribute.Left, relatedBy: NSLayoutRelation.Equal, toItem: self.myView, attribute: NSLayoutAttribute.Left, multiplier: 1.0, constant: 0))
        self.myView.addConstraint(NSLayoutConstraint(item: self.addressBarController.view, attribute: NSLayoutAttribute.Width, relatedBy: NSLayoutRelation.Equal, toItem: self.myView, attribute: NSLayoutAttribute.Width, multiplier: 1.0, constant:0))
        self.myView.addConstraint(NSLayoutConstraint(item: self.addressBarController.view, attribute: NSLayoutAttribute.Top, relatedBy: NSLayoutRelation.Equal, toItem: self.topLayoutGuide, attribute: NSLayoutAttribute.Bottom, multiplier: 1.0, constant: 0))
        self.myView.addConstraint(NSLayoutConstraint(item: self.addressBarController.view, attribute: NSLayoutAttribute.Bottom, relatedBy: NSLayoutRelation.Equal, toItem: self.myView, attribute: NSLayoutAttribute.Bottom, multiplier: 1.0, constant: 0))
    }

    // MARK:- Notification Registration

    func atl_baseRegisterForNotifications() {
        // Keyboard Notifications
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("keyboardWillShow:"), name: UIKeyboardWillShowNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("keyboardWillHide:"), name: UIKeyboardWillHideNotification, object: nil)
        
        // ATLMessageInputToolbar Notifications
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("textViewTextDidBeginEditing:"), name: UITextViewTextDidBeginEditingNotification, object: self.messageInputToolbar.textInputView)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("messageInputToolbarDidChangeHeight:"), name: ATLMessageInputToolbarDidChangeHeightNotification, object: self.messageInputToolbar)
    }
}