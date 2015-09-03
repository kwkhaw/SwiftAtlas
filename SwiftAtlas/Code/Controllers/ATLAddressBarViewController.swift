import UIKit
import LayerKit

@objc protocol ATLAddressBarViewControllerDelegate : NSObjectProtocol {
    /**
     @abstract Informs the delegate that a user began searching by typing in the `LYRAddressBarTextView`.
     @param addressBarViewController The `ATLAddressBarViewController` presenting the `ATLAddressBarTextView`.
     */
    optional func addressBarViewControllerDidBeginSearching(addressBarViewController: ATLAddressBarViewController)

    /**
     @abstract Informs the delegate that the user made a participant selection.
     @param addressBarViewController The `ATLAddressBarViewController` in which the selection occurred.
     @param participant The participant who was selected and added to the address bar.
     @discussion Upon selection, the participant's full name will be appended to any existing text in the `ATLAddressBarTextView`.
     The set of participants represents the identifiers for all currently displayed participants.
     */
    optional func addressBarViewController(addressBarViewController: ATLAddressBarViewController, didSelectParticipant participant: ATLParticipant)

    /**
     @abstract Informs the delegate that the user removed a participant from the address bar.
     @param addressBarViewController The `ATLAddressBarViewController` in which the removal occurred.
     @param participant The participant who was removed.
     */
    optional func addressBarViewController(addressBarViewController: ATLAddressBarViewController, didRemoveParticipant participant: ATLParticipant)

    /**
     @abstract Informs the delegate that the user finished searching.
     @param addressBarViewController The `ATLAddressBarViewController` in which the search occurred.
     @discussion Searching ends when the user either selects a participant or removes all participants from the `ATLAddressBarTextView`.
     */
    optional func addressBarViewControllerDidEndSearching(addressBarViewController: ATLAddressBarViewController)

    /**
     @abstract Informs the delegate that the user tapped on the `addContactsButton`.
     @param addressBarViewController The `ATLAddressBarViewController` in which the tap occurred.
     @param addContactsButton The button that was tapped.
     */
    optional func addressBarViewController(addressBarViewController: ATLAddressBarViewController, didTapAddContactsButton addContactsButton: UIButton)

    /**
     @abstract Informs the delegate that the user tapped on the controller while in a disabled state.
     @param addressBarViewController The `ATLAddressBarViewController` in which the tap occurred.
     */
    optional func addressBarViewControllerDidSelectWhileDisabled(addressBarViewController: ATLAddressBarViewController)

    /**
     @abstract Asks the data source for an NSSet of participants given a search string.
     @param addressBarViewController The `ATLAddressBarViewController` in which the tap occurred.
     @param searchText The text upon which a participant search should be performed.
     @param completion The completion block to be called upon search completion.
     @discussion Search should be performed across each `ATLParticipant` object's fullName property.
     */
    optional func addressBarViewController(addressBarViewController: ATLAddressBarViewController, searchForParticipantsMatchingText searchText: String, completion: (participants: [ATLParticipant]) -> Void)
        
}

// FIXME: Change to public
class ATLAddressBarViewController: UIViewController, UITextViewDelegate, UITableViewDataSource, UITableViewDelegate {
    /**
     @abstract The object to be informed of specific events that occur within the controller.
     */
    // FIXME: Change to public
    var delegate: ATLAddressBarViewControllerDelegate? = nil

    /**
     @abstract The `ATLAddressBarView` displays the `ATLAddressBarTextView` in which the actual text input occurs. It also displays
     a UIButton object represented by the `addContactButton` property.
     */
    // FIXME: Change to public
    var addressBarView: ATLAddressBarView! = nil

    ///------------------------------------
    // @name Managing Participant Selection
    ///------------------------------------

    /**
     @abstract An ordered set of the currently selected participants.
     */
    // FIXME: Change to public
    private var _selectedParticipants: NSOrderedSet = NSOrderedSet()
    
    var tableView: UITableView! = nil
    var participants: [ATLParticipant] = [ATLParticipant]()
    var disabled: Bool = false
    
    /**
    @abstract A boolean indicating whether or not the receiver is in a disabled state.
    */
    var isDisabled: Bool {
        get {
            return disabled
        }
    }
    
    let ATLDisabledStringPadding: CGFloat = 20;
    let ATLAddressBarViewAccessibilityLabel = "Address Bar View"
    let ATLAddressBarAccessibilityLabel = "Address Bar"
    private let ATLMParticpantCellIdentifier = "participantCellIdentifier"
    private let ATLAddressBarParticipantAttributeName = "ATLAddressBarParticipant"

    override func loadView() {
        self.view = ATLAddressBarContainerView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.accessibilityLabel = ATLAddressBarAccessibilityLabel
        self.view.translatesAutoresizingMaskIntoConstraints = false
        
        self.addressBarView = ATLAddressBarView()
        self.addressBarView.translatesAutoresizingMaskIntoConstraints = false
        self.addressBarView.accessibilityLabel = ATLAddressBarViewAccessibilityLabel
        self.addressBarView.backgroundColor = ATLAddressBarGray()
        self.addressBarView.addressBarTextView.delegate = self
        self.addressBarView.addContactsButton.addTarget(self, action: Selector("contactButtonTapped:"), forControlEvents: UIControlEvents.TouchUpInside)
        self.view.addSubview(self.addressBarView)
       
        self.tableView = UITableView()
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.rowHeight = 56
        self.tableView.registerClass(UITableViewCell.self, forCellReuseIdentifier: ATLMParticpantCellIdentifier)
        self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissMode.OnDrag
        self.tableView.hidden = true
        self.view.addSubview(self.tableView)
        
        configureLayoutConstraintsForAddressBarView()
        configureLayoutConstraintsForTableView()
    }

    // MARK:- Public Method Implementation

    ///----------------------
    /// @name Disabling Input
    ///----------------------
    
    /**
    @abstract Disables user input and searching.
    */
    func disable() {
        if self.isDisabled {
            return
        }
        
        self.disabled = true

        self.addressBarView.addressBarTextView.text = disabledStringForParticipants(self.selectedParticipants)
        self.addressBarView.addressBarTextView.textColor = ATLGrayColor()
        self.addressBarView.addressBarTextView.editable = false
        self.addressBarView.addressBarTextView.userInteractionEnabled = false
        self.addressBarView.addContactsButton.hidden = true
        
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: Selector("addressBarTappedWhileDisabled:"))
        self.view.addGestureRecognizer(gestureRecognizer)
        
        sizeAddressBarView()
    }

    /**
    @abstract Informs the receiver that a selection occurred outside of the controller and a participant should be added to the address
    bar.
    @param participant The participant to select.
    */
    func selectParticipant(participant: ATLParticipant?) {
        if participant == nil {
            return
        }

        // FIXME: Can be replaced with Set?
        let participants: NSMutableOrderedSet = NSMutableOrderedSet(orderedSet: self.selectedParticipants)
        participants.addObject(participant!)
        self.selectedParticipants = participants
    }

    // TODO: Can be replaced with property observer?
    // FIXME: Review the logic in this function!
    @nonobjc // http://stackoverflow.com/questions/29457720/compiler-error-method-with-objective-c-selector-conflicts-with-previous-declara/29670644#29670644
    var selectedParticipants: NSOrderedSet {
        get {
            return _selectedParticipants
        }
        
        set {
            if newValue.count == 0 && self.selectedParticipants.count == 0 {
                return
            }
            if newValue.count > 0 && newValue.isEqual(self.selectedParticipants) {
                return
            }

            if self.isDisabled {
                let text: String = disabledStringForParticipants(selectedParticipants)
                self.addressBarView.addressBarTextView.text = text
            } else {
                let attributedText: NSAttributedString = attributedStringForParticipants(selectedParticipants)
                self.addressBarView.addressBarTextView.attributedText = attributedText
            }
            sizeAddressBarView()
            
            let existingParticipants: NSOrderedSet = self.selectedParticipants
            self.selectedParticipants = newValue
            
            if self.isDisabled {
                return
            }
            
            let removedParticipants: NSMutableOrderedSet = NSMutableOrderedSet(orderedSet: existingParticipants)
            if newValue.count > 0 {
                removedParticipants.minusOrderedSet(newValue)
            }
            notifyDelegateOfRemovedParticipants(removedParticipants)
            
            let addedParticipants: NSMutableOrderedSet = NSMutableOrderedSet(orderedSet: newValue)
            if existingParticipants.count > 0 {
                addedParticipants.minusOrderedSet(existingParticipants)
            }
            notifyDelegateOfSelectedParticipants(addedParticipants)
            
            searchEnded()
        }
    }

    ///-------------------------
    /// @name Reloading the View
    ///-------------------------
    
    /**
    @abstract Tells the receiver to reload the view with the latest details of the participants.
    */
    func reloadView() {
        tableView.reloadData()
    }

    // MARK:- UITableViewDataSource

    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.participants.count
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell: UITableViewCell = tableView.dequeueReusableCellWithIdentifier(ATLMParticpantCellIdentifier)!
        // FIXME: cell definitely will not be null??
        let participant: ATLParticipant  = self.participants[indexPath.row]
        cell.textLabel!.text = participant.fullName
        cell.textLabel!.font = ATLMediumFont(16)
        cell.textLabel!.textColor = ATLBlueColor()
        return cell
    }

    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let  participant: ATLParticipant = self.participants[indexPath.row]
        selectParticipant(participant)
    }

    // MARK:- UIScrollViewDelegate

    func scrollViewDidScroll(scrollView: UIScrollView) {
        if scrollView != self.addressBarView.addressBarTextView {
            return
        }
        if CGSizeEqualToSize(scrollView.frame.size, scrollView.contentSize) {
            scrollView.contentOffset = CGPointZero
        }
    }

    // MARK:- UITextViewDelegate

    func textViewShouldBeginEditing(textView: UITextView) -> Bool {
        self.addressBarView.addContactsButton.hidden = false
        return true
    }

    func textViewShouldEndEditing(textView: UITextView) -> Bool {
        self.addressBarView.addContactsButton.hidden = true
        return true
    }

    func textView(textView: UITextView, shouldChangeTextInRange range: NSRange, replacementText text: String) -> Bool {
        if textView.typingAttributes[NSForegroundColorAttributeName] != nil {
            textView.typingAttributes[NSForegroundColorAttributeName] = self.addressBarView.addressBarTextView.addressBarTextColor
        }

        // If user is deleting...
        if text.isEmpty {
            let attributedString: NSAttributedString = textView.attributedText
            // If range.length is 1, we need to select the participant
            if range.length == 1 {
                var effectiveRange: NSRange = NSMakeRange(0, 1)
                let  participant: ATLParticipant? = attributedString.attribute(ATLAddressBarParticipantAttributeName, atIndex: range.location, longestEffectiveRange: &effectiveRange, inRange: NSMakeRange(0, attributedString.length)) as? ATLParticipant
                if participant != nil && (effectiveRange.location + effectiveRange.length == range.location + range.length) {
                    textView.selectedRange = effectiveRange
                    return false
                }
            }
        } else if text.characters.contains("\n") {
            return false
        }
        return true
    }

    func textViewDidChangeSelection(textView: UITextView) {
        let selectedRange: NSRange = textView.selectedRange
        let acceptableRange: NSRange = acceptableSelectedRange()
        if !NSEqualRanges(acceptableRange, selectedRange) {
            textView.selectedRange = acceptableRange
        }
        // Workaround for automatic scrolling not occurring in some cases after text entry.
        textView.scrollRangeToVisible(textView.selectedRange)
    }

    func textViewDidChange(textView: UITextView) {
        let attributedString: NSAttributedString = textView.attributedText
        let participants: NSOrderedSet = participantsInAttributedString(attributedString)
        let removedParticipants: NSMutableOrderedSet = NSMutableOrderedSet(orderedSet: self.selectedParticipants)
        removedParticipants.minusOrderedSet(participants)
        self.selectedParticipants = participants
        if let delegate = self.delegate {
            if delegate.respondsToSelector(Selector("addressBarViewController:didRemoveParticipant:")) {
                for participant in removedParticipants {
                    delegate.addressBarViewController!(self, didRemoveParticipant: participant as! ATLParticipant)
                }
            }
        }

        sizeAddressBarView()
        let enteredText: String = textView.text
        let searchText: String? = textForSearchFromTextView(textView)
        // If no text, reset search bar
        if searchText == nil || searchText!.isEmpty {
            searchEnded()
        } else {
            if self.tableView.hidden {
                self.tableView.hidden = false
                self.delegate?.addressBarViewControllerDidBeginSearching?(self)
            }
            self.delegate?.addressBarViewController?(self, searchForParticipantsMatchingText: searchText!, completion: { (participants) in
                if enteredText != textView.text {
                    return
                }
                self.tableView.hidden = false
                self.participants = self.filteredParticipants(participants)
                self.tableView.reloadData()
                self.tableView.setContentOffset(CGPointZero, animated: false)
            })
        }
    }

    // MARK:- Actions

    func addressBarTextViewTapped(recognizer: UITapGestureRecognizer) {
        if self.disabled {
            return
        }
        
        // Make sure the addressTextView is first responder
        if !self.addressBarView.addressBarTextView.isFirstResponder() {
            self.addressBarView.addressBarTextView.becomeFirstResponder()
        }
        
        // Calculate the tap index
        let textView: UITextView = recognizer.view as! UITextView
        let tapPoint: CGPoint = recognizer.locationInView(textView)
        let tapTextPosition: UITextPosition = textView.closestPositionToPoint(tapPoint)!
        let tapIndex: Int = self.addressBarView.addressBarTextView.offsetFromPosition(self.addressBarView.addressBarTextView.beginningOfDocument, toPosition: tapTextPosition)
        let attributedString: NSAttributedString = self.addressBarView.addressBarTextView.attributedText
        if tapIndex == 0 {
            textView.selectedRange = NSMakeRange(0, 0)
            return
        }
        if tapIndex == attributedString.length {
            textView.selectedRange = NSMakeRange(attributedString.length, 0)
            return
        }
        var participantRange: NSRange = NSMakeRange(0, 1)
        let participant: ATLParticipant? = attributedString.attribute(ATLAddressBarParticipantAttributeName, atIndex: tapIndex - 1, longestEffectiveRange: &participantRange, inRange: NSMakeRange(0, attributedString.length)) as? ATLParticipant
        if participant != nil {
            textView.selectedRange = participantRange
        } else {
            textView.selectedRange = NSMakeRange(tapIndex, 0)
        }
    }

    func addressBarTappedWhileDisabled(sender: AnyObject) {
        notifyDelegateOfDisableTap()
    }

    func contactButtonTapped(sender: UIButton) {
        notifyDelegateOfContactButtonTap(sender)
    }

    // MARK:- Delegate Implementation

    func notifyDelegateOfSelectedParticipants(selectedParticipants: NSMutableOrderedSet) {
        guard let delegate = self.delegate else { return }
        if delegate.respondsToSelector(Selector("addressBarViewController:didSelectParticipant:")) {
            for addedParticipant in selectedParticipants {
                delegate.addressBarViewController!(self, didSelectParticipant: addedParticipant as! ATLParticipant)
            }
        }
    }

    func notifyDelegateOfRemovedParticipants(removedParticipants: NSMutableOrderedSet) {
        guard let delegate = self.delegate else { return }
        if delegate.respondsToSelector(Selector("addressBarViewController:didRemoveParticipant:")) {
            for removedParticipant in removedParticipants {
                delegate.addressBarViewController!(self, didRemoveParticipant: removedParticipant as! ATLParticipant)
            }
        }
    }

    func notifyDelegateOfSearchEnd() {
        self.delegate?.addressBarViewControllerDidEndSearching?(self)
    }

    func notifyDelegateOfDisableTap() {
        self.delegate?.addressBarViewControllerDidSelectWhileDisabled?(self)
    }

    func notifyDelegateOfContactButtonTap(sender: UIButton) {
        self.delegate?.addressBarViewController?(self, didTapAddContactsButton: sender)
    }

    // MARK:- Helpers

    func sizeAddressBarView() {
        // We layout addressBarTextView as it drives the address bar size.
        self.addressBarView.addressBarTextView.setNeedsLayout()
    }

    func textForSearchFromTextView(textView: UITextView) -> String? {
        let attributedString: NSAttributedString = textView.attributedText
        var searchRange: NSRange = NSMakeRange(NSNotFound, 0)
        attributedString.enumerateAttribute(ATLAddressBarParticipantAttributeName, inRange: NSMakeRange(0, attributedString.length), options: NSAttributedStringEnumerationOptions.LongestEffectiveRangeNotRequired, usingBlock: { (participant, range, stop) in
            if participant != nil {
                return
            }
            searchRange = range
        })
        if (searchRange.location == NSNotFound) {
            return nil
        }
        let attributedSearchString: NSAttributedString = attributedString.attributedSubstringFromRange(searchRange)
        let searchString: String = attributedSearchString.string
        let trimmedSearchString: String = searchString.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
        return trimmedSearchString
    }

    func filteredParticipants(participants: [ATLParticipant]) -> [ATLParticipant] {
        // Any easier way??
//        return participants.difference(self.selectedParticipants.array)
        
//        let selectedParticipants = self.selectedParticipants.array
//        return participants.filter { participant in
//            !selectedParticipants.contains(participant)
//        }
        let theParticipants: NSMutableArray = NSMutableArray(array: participants)
        theParticipants.removeObjectsInArray(self.selectedParticipants.array)
        // Sigh... http://dev.eltima.com/post/96538497489/convert-nsmutablearray-to-swift-array
        return theParticipants as [AnyObject] as! [ATLParticipant]
    }

    func searchEnded() {
        if self.tableView.hidden {
            return
        }
        notifyDelegateOfSearchEnd()
        self.participants = []
        self.tableView.hidden = true
        self.tableView.reloadData()
    }

    func participantsInAttributedString(attributedString: NSAttributedString) -> NSOrderedSet {
        let participants: NSMutableOrderedSet = NSMutableOrderedSet()
        attributedString.enumerateAttribute(ATLAddressBarParticipantAttributeName, inRange: NSMakeRange(0, attributedString.length),  options: NSAttributedStringEnumerationOptions.LongestEffectiveRangeNotRequired, usingBlock: { (participant, range, stop) in
            if participant == nil {
                return
            }
            participants.addObject(participant!)
        })
        return participants
    }

    func attributedStringForParticipants(participants: NSOrderedSet) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        for participant in participants {
            let attributedParticipant: NSAttributedString = attributedStringForParticipant(participant as! ATLParticipant)
            attributedString.appendAttributedString(attributedParticipant)
        }
        return attributedString
    }

    func attributedStringForParticipant(participant: ATLParticipant) -> NSAttributedString {
        let textView: ATLAddressBarTextView = self.addressBarView.addressBarTextView
        let attributedString = NSMutableAttributedString()

        let attributedName: NSAttributedString = NSAttributedString(string: participant.fullName, attributes: [ATLAddressBarPartAttributeName: ATLAddressBarNamePart, ATLAddressBarPartAttributeName: ATLAddressBarNamePart, NSForegroundColorAttributeName: textView.addressBarHighlightColor])
        attributedString.appendAttributedString(attributedName)

        let attributedDelimiter = NSAttributedString(string: ", ", attributes: [ATLAddressBarPartAttributeName: ATLAddressBarDelimiterPart, NSForegroundColorAttributeName: UIColor.grayColor()])
        attributedString.appendAttributedString(attributedDelimiter)

        attributedString.addAttributes([ATLAddressBarParticipantAttributeName: participant, NSFontAttributeName: textView.font!, NSParagraphStyleAttributeName: textView.typingAttributes[NSParagraphStyleAttributeName]!], range: NSMakeRange(0, attributedString.length))

        return attributedString
    }

    func acceptableSelectedRange() -> NSRange {
        let selectedRange: NSRange = self.addressBarView.addressBarTextView.selectedRange
        let attributedString: NSAttributedString = self.addressBarView.addressBarTextView.attributedText
        if selectedRange.length == 0 {
            if selectedRange.location == 0 {
                return selectedRange
            }
            if selectedRange.location == attributedString.length {
                return selectedRange
            }
            var participantRange: NSRange = NSMakeRange(0, 1)
            let participant: ATLParticipant? = attributedString.attribute(ATLAddressBarParticipantAttributeName, atIndex: selectedRange.location, longestEffectiveRange: &participantRange, inRange: NSMakeRange(0, attributedString.length)) as? ATLParticipant
            if participant == nil {
                return selectedRange
            }
            if selectedRange.location <= participantRange.location {
                return selectedRange
            }
            let participantStartIndex: Int = participantRange.location
            let participantEndIndex: Int = participantRange.location + participantRange.length
            let closerToParticipantStart: Bool = selectedRange.location - participantStartIndex < participantEndIndex - selectedRange.location
            if closerToParticipantStart {
                return NSMakeRange(participantStartIndex, 0)
            } else {
                return NSMakeRange(participantEndIndex, 0)
            }
        }

        var adjustedRange: NSRange = selectedRange
        attributedString.enumerateAttribute(ATLAddressBarParticipantAttributeName, inRange: NSMakeRange(0, attributedString.length), options: NSAttributedStringEnumerationOptions.LongestEffectiveRangeNotRequired, usingBlock: { (participant, range, stop) in
            if participant == nil {
                return
            }
            if NSIntersectionRange(selectedRange, range).length == 0 {
                return
            }
            adjustedRange = NSUnionRange(adjustedRange, range)
        })

        return adjustedRange
    }

    // MARK:- Disabled String Helpers

    func disabledStringForParticipants(participants: NSOrderedSet) -> String {
        addressBarView.addressBarTextView.layoutIfNeeded() // Layout text view so we can have an accurate width.
        
        var disabledString: String = participants.firstObject!.firstName
        let mutableParticipants: NSMutableOrderedSet = NSMutableOrderedSet(orderedSet: participants)
        mutableParticipants.removeObject(participants.firstObject!)
        
        var remainingParticipants: Int = mutableParticipants.count
        mutableParticipants.enumerateObjectsUsingBlock { (participant, idx, stop) in
            var othersString: String = self.otherStringWithRemainingParticipants(remainingParticipants)
            let truncatedString: String = "\(disabledString) \(othersString)"
            if self.textViewHasSpaceForParticipantString(truncatedString) {
                remainingParticipants -= 1
                othersString = self.otherStringWithRemainingParticipants(remainingParticipants)
                let expandedString: String = "\(disabledString), \(participant.firstName) \(othersString)"
                if self.textViewHasSpaceForParticipantString(expandedString) {
                    disabledString = "\(disabledString), \(participant.firstName)"
                } else {
                    disabledString = truncatedString
                    stop.memory = true
                }
            } else {
                disabledString = "\(remainingParticipants) participants"
                stop.memory = true
            }
        }
        return disabledString;
    }

    func otherStringWithRemainingParticipants(remainingParticipants: Int) -> String {
        let othersString = (remainingParticipants > 1) ? "others" : "other"
        return "and \(remainingParticipants) \(othersString)"
    }

    func textViewHasSpaceForParticipantString(participantString: String) -> Bool {
        let fittedSize: CGSize = participantString.sizeWithAttributes([NSFontAttributeName: self.addressBarView.addressBarTextView.font!])
        return fittedSize.width < (CGRectGetWidth(self.addressBarView.addressBarTextView.frame) - ATLAddressBarTextViewIndent - ATLAddressBarTextContainerInset - ATLDisabledStringPadding) // Adding extra padding to account for text container inset.
    }

    // MARK:- Auto Layout

    func configureLayoutConstraintsForAddressBarView() {
        view.addConstraint(NSLayoutConstraint(item:self.addressBarView, attribute: NSLayoutAttribute.Width, relatedBy: NSLayoutRelation.Equal, toItem: view, attribute: NSLayoutAttribute.Width, multiplier: 1.0, constant: 0))
        view.addConstraint(NSLayoutConstraint(item:self.addressBarView, attribute: NSLayoutAttribute.Top, relatedBy: NSLayoutRelation.Equal, toItem: view, attribute: NSLayoutAttribute.Top, multiplier: 1.0, constant: 0))
        view.addConstraint(NSLayoutConstraint(item:self.addressBarView, attribute: NSLayoutAttribute.Left, relatedBy: NSLayoutRelation.Equal, toItem: view, attribute: NSLayoutAttribute.Left, multiplier: 1.0, constant: 0))
     }

    func configureLayoutConstraintsForTableView() {
        view.addConstraint(NSLayoutConstraint(item: self.tableView, attribute: NSLayoutAttribute.Width, relatedBy: NSLayoutRelation.Equal, toItem: view, attribute: NSLayoutAttribute.Width, multiplier: 1.0, constant: 0))
        view.addConstraint(NSLayoutConstraint(item: self.tableView, attribute: NSLayoutAttribute.Bottom, relatedBy: NSLayoutRelation.Equal, toItem: view, attribute: NSLayoutAttribute.Bottom, multiplier: 1.0, constant:0))
        view.addConstraint(NSLayoutConstraint(item: self.tableView, attribute: NSLayoutAttribute.Top, relatedBy: NSLayoutRelation.Equal, toItem: addressBarView, attribute: NSLayoutAttribute.Bottom, multiplier: 1.0, constant:0))
        view.addConstraint(NSLayoutConstraint(item: self.tableView, attribute: NSLayoutAttribute.Left, relatedBy: NSLayoutRelation.Equal, toItem: view, attribute: NSLayoutAttribute.Left, multiplier: 1.0, constant:0))
    }
}