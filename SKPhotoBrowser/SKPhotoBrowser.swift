//
//  SKPhotoBrowser.swift
//  SKViewExample
//
//  Created by suzuki_keishi on 2015/10/01.
//  Copyright © 2015 suzuki_keishi. All rights reserved.
//

import UIKit

public let SKPHOTO_LOADING_DID_END_NOTIFICATION = "photoLoadingDidEndNotification"

// MARK: - SKPhotoBrowser
open class SKPhotoBrowser: UIViewController {
    // open function
    open var currentPageIndex: Int = 0 {
        didSet {
            self.setupToolBarButtoms()
        }
    }
    open var initPageIndex: Int = 0
    open var activityItemProvider: UIActivityItemProvider?
    open var photos: [SKPhotoProtocol] = []
    
    internal lazy var pagingScrollView: SKPagingScrollView = SKPagingScrollView(frame: self.view.frame, browser: self)
    
    var playbackControlsView: VideoPlaybackControlsView? = LoadFromNib(viewOfClass: VideoPlaybackControlsView.self)
    
    // appearance
    fileprivate let bgColor: UIColor = SKPhotoBrowserOptions.backgroundColor
    // animation
    let animator: SKAnimator = .init()
    
    // child component
    fileprivate var actionView: SKActionView!
    fileprivate(set) var paginationView: SKPaginationView!
    var toolbar: SKToolbar!

    // actions
    fileprivate var activityViewController: UIActivityViewController!
    fileprivate var panGesture: UIPanGestureRecognizer?

    // for status check property
    fileprivate var isEndAnimationByToolBar: Bool = true
    fileprivate var isViewActive: Bool = false
    fileprivate var isPerformingLayout: Bool = false
    
    // pangesture property
    fileprivate var firstX: CGFloat = 0.0
    fileprivate var firstY: CGFloat = 0.0
    
    // timer
    fileprivate var controlVisibilityTimer: Timer!
    
    // delegate
    open weak var delegate: SKPhotoBrowserDelegate?

    // statusbar initial state
    private var statusbarHidden: Bool = UIApplication.shared.isStatusBarHidden
    
    // strings
    open var cancelTitle = "Cancel"

    // MARK: - Initializer
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    public override init(nibName nibNameOrNil: String!, bundle nibBundleOrNil: Bundle!) {
        super.init(nibName: nil, bundle: nil)
        setup()
    }
    
    public convenience init(photos: [SKPhotoProtocol]) {
        self.init(photos: photos, initialPageIndex: 0)
    }
    
    @available(*, deprecated)
    public convenience init(originImage: UIImage, photos: [SKPhotoProtocol], animatedFromView: UIView) {
        self.init(nibName: nil, bundle: nil)
        self.photos = photos
        self.photos.forEach { $0.checkCache() }
        animator.senderOriginImage = originImage
        animator.senderViewForAnimation = animatedFromView
    }
    
    public convenience init(photos: [SKPhotoProtocol], initialPageIndex: Int) {
        self.init(nibName: nil, bundle: nil)
        self.photos = photos
        self.photos.forEach { $0.checkCache() }
        self.currentPageIndex = min(initialPageIndex, photos.count - 1)
        self.initPageIndex = self.currentPageIndex
        animator.senderOriginImage = photos[currentPageIndex].underlyingImage
        animator.senderViewForAnimation = photos[currentPageIndex] as? UIView
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func setup() {
        modalPresentationCapturesStatusBarAppearance = true
        modalPresentationStyle = .custom
        modalTransitionStyle = .crossDissolve
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleSKPhotoLoadingDidEndNotification(_:)),
                                               name: NSNotification.Name(rawValue: SKPHOTO_LOADING_DID_END_NOTIFICATION),
                                               object: nil)
    }
    
    // MARK: - override
    override open func viewDidLoad() {
        super.viewDidLoad()
        configureAppearance()
        configurePagingScrollView()
        configureGestureControl()
        configureActionView()
        configurePaginationView()
        configureToolbar()

        animator.willPresent(self)
    }
    
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(true)
        reloadData()
        
        var i = 0
        for photo: SKPhotoProtocol in photos {
            photo.index = i
            i += 1
        }
    }
    
    override open func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        isPerformingLayout = true
        // where did start
        delegate?.didShowPhotoAtIndex?(self, index: currentPageIndex)

        // toolbar
        toolbar.frame = frameForToolbarAtOrientation()
        
        // action
        actionView.updateFrame(frame: view.frame)

        // paging
        switch SKCaptionOptions.captionLocation {
        case .basic:
            paginationView.updateFrame(frame: view.frame)
        case .bottom:
            paginationView.frame = frameForPaginationAtOrientation()
        }
        pagingScrollView.updateFrame(view.bounds, currentPageIndex: currentPageIndex)

        self.setupToolBarButtoms()
        isPerformingLayout = false
    }
    
    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        isViewActive = true
        self.hideControlsAfterDelay()
    }
    
    override open var prefersStatusBarHidden: Bool {
        return !SKPhotoBrowserOptions.displayStatusbar
    }
    
    override open var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    // MARK: - Notification
    @objc open func handleSKPhotoLoadingDidEndNotification(_ notification: Notification) {
        guard let photo = notification.object as? SKPhotoProtocol else {
            return
        }
        
        DispatchQueue.main.async(execute: {
            guard let page = self.pagingScrollView.pageDisplayingAtPhoto(photo), let photo = page.photo else {
                return
            }
            
            if photo.underlyingImage != nil {
                page.displayImage(complete: true)
                self.loadAdjacentPhotosIfNecessary(photo)
            } else {
                page.displayImageFailure()
            }
        })
    }
    
    open func loadAdjacentPhotosIfNecessary(_ photo: SKPhotoProtocol) {
        pagingScrollView.loadAdjacentPhotosIfNecessary(photo, currentPageIndex: currentPageIndex)
    }
    
    // MARK: - initialize / setup
    open func reloadData() {
        performLayout()
        view.setNeedsLayout()
    }
    
    open func performLayout() {
        isPerformingLayout = true

        // reset local cache
        pagingScrollView.reload()
        pagingScrollView.updateContentOffset(currentPageIndex)
        pagingScrollView.tilePages()
        
        delegate?.didShowPhotoAtIndex?(self, index: currentPageIndex)
        
        isPerformingLayout = false
    }
    
    open func prepareForClosePhotoBrowser() {
        cancelControlHiding()
        if let panGesture = panGesture {
            view.removeGestureRecognizer(panGesture)
        }
        NSObject.cancelPreviousPerformRequests(withTarget: self)
    }
    
    open func dismissPhotoBrowser(animated: Bool, completion: (() -> Void)? = nil) {
        prepareForClosePhotoBrowser()
        if !animated {
            modalTransitionStyle = .crossDissolve
        }
        dismiss(animated: !animated) {
            completion?()
            self.delegate?.didDismissAtPageIndex?(self.currentPageIndex)
        }
    }
    
    open func determineAndClose() {
        delegate?.willDismissAtPageIndex?(self.currentPageIndex)
        animator.willDismiss(self)
    }
    
    open func popupShare(includeCaption: Bool = true) {
        let photo = photos[currentPageIndex]
        guard let underlyingImage = photo.underlyingImage else {
            return
        }
        
        var activityItems: [AnyObject] = [underlyingImage]
        if photo.caption != nil && includeCaption {
            if let shareExtraCaption = SKPhotoBrowserOptions.shareExtraCaption {
                let caption = photo.caption ?? "" + shareExtraCaption
                activityItems.append(caption as AnyObject)
            } else {
                activityItems.append(photo.caption as AnyObject)
            }
        }
        
        if let activityItemProvider = activityItemProvider {
            activityItems.append(activityItemProvider)
        }
        
        activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        activityViewController.completionWithItemsHandler = { (activity, success, items, error) in
            self.hideControlsAfterDelay()
            self.activityViewController = nil
        }
        if UI_USER_INTERFACE_IDIOM() == .phone {
            present(activityViewController, animated: true, completion: nil)
        } else {
            activityViewController.modalPresentationStyle = .popover
            let popover: UIPopoverPresentationController! = activityViewController.popoverPresentationController
            popover.barButtonItem = toolbar.toolActionButton
            present(activityViewController, animated: true, completion: nil)
        }
    }
}

// MARK: - Public Function For Customizing Buttons

public extension SKPhotoBrowser {
	func hideMenuButton(_ image: UIImage, size: CGSize? = nil) {
		actionView.updateMenuButton(image: image, size: nil)
	}
	
	func hideToolbar() {
		self.toolbar.setControlsHidden(hidden: true)
	}
}

public extension SKPhotoBrowser {
    func updateCloseButton(_ image: UIImage, size: CGSize? = nil) {
        actionView.updateCloseButton(image: image, size: size)
    }
    
    func updateDeleteButton(_ image: UIImage, size: CGSize? = nil) {
        actionView.updateDeleteButton(image: image, size: size)
    }
    
    func updateOfflineButton() {
        guard  let toolbar = self.toolbar else { return }
        let currentIndex = min(currentPageIndex, self.photos.count - 1)
        let photo = self.photos[currentIndex]
        toolbar.isOffline = photo.isOffline
    }
}

// MARK: - Public Function For Browser Control

public extension SKPhotoBrowser {
    func initializePageIndex(_ index: Int) {
        let i = min(index, photos.count - 1)
        currentPageIndex = i
        
        if isViewLoaded {
            jumpToPageAtIndex(index)
            if !isViewActive {
                pagingScrollView.tilePages()
            }
            paginationView.update(currentPageIndex)
        }
        self.initPageIndex = currentPageIndex
    }
    
    func jumpToPageAtIndex(_ index: Int) {
        if index < photos.count {
            if !isEndAnimationByToolBar {
                return
            }
            isEndAnimationByToolBar = false

            let pageFrame = frameForPageAtIndex(index)
            pagingScrollView.jumpToPageAtIndex(pageFrame)
        }
        hideControlsAfterDelay()
    }
    
    func photoAtIndex(_ index: Int) -> SKPhotoProtocol {
        return photos[index]
    }
    
    @objc func gotoPreviousPage() {
        jumpToPageAtIndex(currentPageIndex - 1)
    }
    
    @objc func gotoNextPage() {
        jumpToPageAtIndex(currentPageIndex + 1)
    }
    
    func cancelControlHiding() {
        if controlVisibilityTimer != nil {
            controlVisibilityTimer.invalidate()
            controlVisibilityTimer = nil
        }
    }
    
    func hideControlsAfterDelay() {
        // reset
        cancelControlHiding()
        // start
        controlVisibilityTimer = Timer.scheduledTimer(timeInterval: 4.0, target: self, selector: #selector(SKPhotoBrowser.hideControls(_:)), userInfo: nil, repeats: false)
    }
    
    func showControls() {
        setControlsHidden(false, animated: true, permanent: false)
    }
    
    func hideControls() {
        setControlsHidden(true, animated: true, permanent: false)
    }
    
    @objc func hideControls(_ timer: Timer) {
        hideControls()
        delegate?.controlsVisibilityToggled?(self, hidden: true)
    }
    
    func toggleControls() {
        let hidden = !areControlsHidden()
        setControlsHidden(hidden, animated: true, permanent: false)
        delegate?.controlsVisibilityToggled?(self, hidden: areControlsHidden())
    }
    
    func areControlsHidden() -> Bool {
        return paginationView.alpha == 0.0
    }
    
    func getCurrentPageIndex() -> Int {
        return currentPageIndex
    }
    
    func addPhotos(photos: [SKPhotoProtocol]) {
        self.photos.append(contentsOf: photos)
        self.reloadData()
    }
    
    func insertPhotos(photos: [SKPhotoProtocol], at index: Int) {
        self.photos.insert(contentsOf: photos, at: index)
        self.reloadData()
    }
}

// MARK: - Internal Function

internal extension SKPhotoBrowser {
    func showButtons() {
        actionView.animate(hidden: false)
    }
    
    func pageDisplayedAtIndex(_ index: Int) -> BasePresentableView? {
        return pagingScrollView.pageDisplayedAtIndex(index)
    }
    
    func getImageFromView(_ sender: UIView) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(sender.frame.size, true, 0.0)
        sender.layer.render(in: UIGraphicsGetCurrentContext()!)
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result!
    }
}

// MARK: - Internal Function For Frame Calc

internal extension SKPhotoBrowser {
    func frameForToolbarAtOrientation() -> CGRect {
        let offset: CGFloat = {
            if #available(iOS 11.0, *) {
                return view.safeAreaInsets.bottom
            } else {
                return 15
            }
        }()
        return view.bounds.divided(atDistance: 44, from: .maxYEdge).slice.offsetBy(dx: 0, dy: -offset)
    }
    
    func frameForToolbarHideAtOrientation() -> CGRect {
        return view.bounds.divided(atDistance: 44, from: .maxYEdge).slice.offsetBy(dx: 0, dy: 44)
    }
    
    func frameForPaginationAtOrientation() -> CGRect {
        let offset = UIDevice.current.orientation.isLandscape ? 35 : 44
        
        return CGRect(x: 0, y: self.view.bounds.size.height - CGFloat(offset), width: self.view.bounds.size.width, height: CGFloat(offset))
    }
    
    func frameForPageAtIndex(_ index: Int) -> CGRect {
        let bounds = pagingScrollView.bounds
        var pageFrame = bounds
        pageFrame.size.width -= (2 * 10)
        pageFrame.origin.x = (bounds.size.width * CGFloat(index)) + 10
        return pageFrame
    }
    
    func setupToolBarButtoms() {
        guard  let toolbar = self.toolbar else { return }
        let currentIndex = min(currentPageIndex, self.photos.count - 1)
        let photo = self.photos[currentIndex]
        toolbar.isLiked = photo.isLiked
        toolbar.isOffline = photo.isOffline
    }
}

// MARK: - Internal Function For Button Pressed, UIGesture Control

internal extension SKPhotoBrowser {
    @objc func panGestureRecognized(_ sender: UIPanGestureRecognizer) {
        guard let zoomingScrollView = pagingScrollView.pageDisplayedAtIndex(currentPageIndex) else {
            return
        }
        
        animator.backgroundView.isHidden = true
        let viewHeight: CGFloat = zoomingScrollView.frame.size.height
        let viewHalfHeight: CGFloat = viewHeight/2
        var translatedPoint: CGPoint = sender.translation(in: self.view)
        
        // gesture began
        if sender.state == .began {
            firstX = zoomingScrollView.center.x
            firstY = zoomingScrollView.center.y
            
            hideControls()
            setNeedsStatusBarAppearanceUpdate()
        }
        
        translatedPoint = CGPoint(x: firstX, y: firstY + translatedPoint.y)
        zoomingScrollView.center = translatedPoint
        
        let minOffset: CGFloat = viewHalfHeight / 4
        let offset: CGFloat = 1 - (zoomingScrollView.center.y > viewHalfHeight
            ? zoomingScrollView.center.y - viewHalfHeight
            : -(zoomingScrollView.center.y - viewHalfHeight)) / viewHalfHeight
        
        view.backgroundColor = bgColor.withAlphaComponent(max(0.7, offset))
        
        // gesture end
        if sender.state == .ended {
            
            if zoomingScrollView.center.y > viewHalfHeight + minOffset
                || zoomingScrollView.center.y < viewHalfHeight - minOffset {
                
                determineAndClose()
                
            } else {
                // Continue Showing View
                setNeedsStatusBarAppearanceUpdate()
                view.backgroundColor = bgColor

                let velocityY: CGFloat = CGFloat(0.35) * sender.velocity(in: self.view).y
                let finalX: CGFloat = firstX
                let finalY: CGFloat = viewHalfHeight
                
                let animationDuration: Double = Double(abs(velocityY) * 0.0002 + 0.2)
                
                UIView.beginAnimations(nil, context: nil)
                UIView.setAnimationDuration(animationDuration)
                UIView.setAnimationCurve(UIView.AnimationCurve.easeIn)
                zoomingScrollView.center = CGPoint(x: finalX, y: finalY)
                UIView.commitAnimations()
            }
        }
    }
    
    func deleteImage() {
        defer {
            reloadData()
        }
        
        if photos.count > 1 {
            pagingScrollView.deleteImage()
            
            photos.remove(at: currentPageIndex)
            if currentPageIndex != 0 {
                gotoPreviousPage()
            }
            paginationView.update(currentPageIndex)
            
        } else if photos.count == 1 {
            dismissPhotoBrowser(animated: true)
        }
    }
    
    func hidePlaybackControls() {
        UIView.animate(withDuration: Constants.animationTime) {
             self.playbackControlsView?.alpha = 0
        }
    }
    
    func showPlaybackControls() {
        guard let playbackControlsView = self.playbackControlsView else { return }
        self.view.bringSubviewToFront(playbackControlsView)
        UIView.animate(withDuration: Constants.animationTime) {
            playbackControlsView.alpha = 1
        }
    }
}

// MARK: - Private Function
private extension SKPhotoBrowser {
    func configureAppearance() {
        view.backgroundColor = bgColor
        view.clipsToBounds = true
        view.isOpaque = false
        
        if #available(iOS 11.0, *) {
            view.accessibilityIgnoresInvertColors = true
        }
    }
    
    func configurePagingScrollView() {
        pagingScrollView.delegate = self
        view.addSubview(pagingScrollView)
        /// FIXME: Если по нормальному засовывать вьюху в SkVideoPlayerView, абсолютно непонятно по-какой причине  ломается  пагинция у скролл вью.
        self.addVideoPlaybackControls()
    }

    func configureGestureControl() {
        guard !SKPhotoBrowserOptions.disableVerticalSwipe else { return }
        
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(SKPhotoBrowser.panGestureRecognized(_:)))
        panGesture?.minimumNumberOfTouches = 1
        panGesture?.maximumNumberOfTouches = 1

        if let panGesture = panGesture {
            view.addGestureRecognizer(panGesture)
        }
    }
    
    func configureActionView() {
        actionView = SKActionView(frame: view.frame, browser: self)
        view.addSubview(actionView)
        actionView.translatesAutoresizingMaskIntoConstraints = false
        actionView.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        actionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        actionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        actionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
    }

    func configurePaginationView() {
        paginationView = SKPaginationView(frame: view.frame, browser: self)
        view.addSubview(paginationView)
    }
    
    func configureToolbar() {
        toolbar = SKToolbar(frame: frameForToolbarAtOrientation(), browser: self)
        view.addSubview(toolbar)
    }

    func setControlsHidden(_ hidden: Bool, animated: Bool, permanent: Bool) {
        // timer update
        cancelControlHiding()
        
        // scroll animation
        pagingScrollView.setControlsHidden(hidden: hidden)
        
        // 
        self.hidePlaybackControls()
        
        // paging animation
        paginationView.setControlsHidden(hidden: hidden)
        
        // action view animation
        actionView.animate(hidden: hidden)
        
        self.toolbar.setControlsHidden(hidden: hidden)
        
        if !hidden && !permanent {
            hideControlsAfterDelay()
        }
        setNeedsStatusBarAppearanceUpdate()
    }
    
    func addVideoPlaybackControls() {
        guard let playbackControlsView = self.playbackControlsView else { return }
        self.playbackControlsView?.translatesAutoresizingMaskIntoConstraints = true
        self.playbackControlsView?.frame = self.calculateFrameForPlayback()
        self.hidePlaybackControls()
        self.view.addSubview(playbackControlsView)
    }
    
    func calculateFrameForPlayback() -> CGRect {
        let frameWidth = self.view.bounds.width
        let playbacksWidth = frameWidth > Constants.playbackConstrolsOtherDevicesWidth
            ? Constants.playbackConstrolsOtherDevicesWidth
            : Constants.playbackConstrolsForSeWidth
        
        let freeSpace: CGFloat = frameWidth - playbacksWidth
        let minY = self.view.bounds.maxY
            - Constants.playbackControlsViewBottomConstant
            - (UIApplication.shared.keyWindow?.safeAreaInsets.bottom ?? 0)
            - Constants.playbackControlsViewHeightConstant
        
        return CGRect(x: self.view.bounds.minX + (freeSpace / 2),
                      y: minY,
                      width: playbacksWidth,
                      height: Constants.playbackControlsViewHeightConstant)
    }
}

// MARK: - UIScrollView Delegate

extension SKPhotoBrowser: UIScrollViewDelegate {
    
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.hidePlaybackControls()
        self.playbackControlsView?.isHidden = true
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard isViewActive else { return }
        guard !isPerformingLayout else { return }
        
        // tile page
        pagingScrollView.tilePages()
        
        // Calculate current page
        let previousCurrentPage = currentPageIndex
        let visibleBounds = pagingScrollView.bounds
        currentPageIndex = min(max(Int(floor(visibleBounds.midX / visibleBounds.width)), 0), photos.count - 1)
        
        if currentPageIndex != previousCurrentPage {
            delegate?.didShowPhotoAtIndex?(self, index: currentPageIndex)
            paginationView.update(currentPageIndex)
        }
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        hideControlsAfterDelay()
        
        let currentIndex = Int(pagingScrollView.contentOffset.x / pagingScrollView.frame.size.width)
        self.pagingScrollView.updateContentOffset(currentIndex)
        
        let isVideo = pagingScrollView.isVideo(at: currentIndex)
        self.playbackControlsView?.isHidden = !isVideo
        isVideo
            ? self.showPlaybackControls()
            : self.hidePlaybackControls()
        
       
        delegate?.didScrollToIndex?(self, index: currentIndex)
    }
    
    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isEndAnimationByToolBar = true
    }
}

private extension SKPhotoBrowser {
    struct Constants {
        static let animationTime: Double = 0.35
        static let iphoneSeScreenWidth = 320
        static let playbackConstrolsForSeWidth: CGFloat = 280
        static let playbackConstrolsOtherDevicesWidth: CGFloat = 320
        static let playbackControlsViewBottomConstant: CGFloat = -70
        static let playbackControlsViewHeightConstant: CGFloat = 80
    }
}
