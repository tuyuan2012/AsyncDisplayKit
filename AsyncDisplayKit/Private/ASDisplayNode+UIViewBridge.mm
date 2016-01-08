/* Copyright (c) 2014-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "_ASCoreAnimationExtras.h"
#import "_ASPendingState.h"
#import "ASInternalHelpers.h"
#import "ASAssert.h"
#import "ASDisplayNodeInternal.h"
#import "ASDisplayNodeExtras.h"
#import "ASDisplayNode+Subclasses.h"
#import "ASDisplayNode+FrameworkPrivate.h"
#import "ASDisplayNode+Beta.h"
#import "ASEqualityHelpers.h"
#import "ASPendingStateController.h"

/**
 * The following macros are conveniences to help in the common tasks related to the bridging that ASDisplayNode does to UIView and CALayer.
 * In general, a property can either be:
 *   - Always sent to the layer or view's layer
 *       use _getFromPendingViewState / _setToLayer
 *   - Bridged to the view if view-backed or the layer if layer-backed
 *       use _getFromViewOrLayer / _setToViewOrLayer / _messageToViewOrLayer
 *   - Only applicable if view-backed
 *       use _setToViewOnly / _getFromPendingViewState
 *   - Has differing types on views and layers, or custom ASDisplayNode-specific behavior is desired
 *       manually implement
 *
 *  _bridge_prologue is defined to take the node's property lock. Add it at the beginning of any bridged methods.
 */

#define DISPLAYNODE_USE_LOCKS 1

#define __loaded (_layer != nil)

#if DISPLAYNODE_USE_LOCKS
#define _bridge_prologue ASDN::MutexLocker l(_propertyLock)
#else
#define _bridge_prologue ()
#endif

/// Returns YES if the property set should be applied to view/layer immediately.
ASDISPLAYNODE_INLINE BOOL ASDisplayNodeMarkDirtyIfNeeded(ASDisplayNode *node) {
  if (NSThread.isMainThread) {
    return node.nodeLoaded;
  } else {
    if (node.nodeLoaded && !node->_pendingViewState.hasChanges) {
      [ASPendingStateController.sharedInstance registerNode:node];
    }
    return NO;
  }
};

#define _setToViewOrLayer(layerProperty, layerValueExpr, viewAndPendingViewStateProperty, viewAndPendingViewStateExpr) BOOL shouldApply = ASDisplayNodeMarkDirtyIfNeeded(self); \
  _pendingViewState.viewAndPendingViewStateProperty = (viewAndPendingViewStateExpr); \
  if (shouldApply) { (_view ? _view.viewAndPendingViewStateProperty = (viewAndPendingViewStateExpr) : _layer.layerProperty = (layerValueExpr)); }

#define _setToViewOnly(viewAndPendingViewStateProperty, viewAndPendingViewStateExpr) BOOL shouldApply = ASDisplayNodeMarkDirtyIfNeeded(self); \
_pendingViewState.viewAndPendingViewStateProperty = (viewAndPendingViewStateExpr); \
if (shouldApply) { _view.viewAndPendingViewStateProperty = (viewAndPendingViewStateExpr); }

#define _getFromPendingViewState(viewAndPendingViewStateProperty) _pendingViewState.viewAndPendingViewStateProperty

#define _setToLayer(layerProperty, layerValueExpr) __loaded ? _layer.layerProperty = (layerValueExpr) : self.pendingViewState.layerProperty = (layerValueExpr)

#define _messageToViewOrLayer(viewAndLayerSelector) __loaded ? (_view ? [_view viewAndLayerSelector] : [_layer viewAndLayerSelector]) : [self.pendingViewState viewAndLayerSelector]

#define _messageToLayer(layerSelector) __loaded ? [_layer layerSelector] : [self.pendingViewState layerSelector]

/**
 * This category implements certain frequently-used properties and methods of UIView and CALayer so that ASDisplayNode clients can just call the view/layer methods on the node,
 * with minimal loss in performance.  Unlike UIView and CALayer methods, these can be called from a non-main thread until the view or layer is created.
 * This allows text sizing in -calculateSizeThatFits: (essentially a simplified layout) to happen off the main thread
 * without any CALayer or UIView actually existing while still being able to set and read properties from ASDisplayNode instances.
 */
@implementation ASDisplayNode (UIViewBridge)

- (BOOL)canBecomeFirstResponder
{
  return NO;
}

- (BOOL)canResignFirstResponder
{
  return YES;
}

#if TARGET_OS_TV
// Focus Engine
- (BOOL)canBecomeFocused
{
  return YES;
}

- (void)setNeedsFocusUpdate
{
  ASDisplayNodeAssertMainThread();
  [_view setNeedsFocusUpdate];
}

- (void)updateFocusIfNeeded
{
  ASDisplayNodeAssertMainThread();
  [_view updateFocusIfNeeded];
}

- (BOOL)shouldUpdateFocusInContext:(UIFocusUpdateContext *)context
{
  return YES;
}

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator
{
  
}

- (UIView *)preferredFocusedView
{
  if (self.nodeLoaded) {
    return _view;
  }
  else {
    return nil;
  }
}
#endif

- (BOOL)isFirstResponder
{
  ASDisplayNodeAssertMainThread();
  return _view != nil && [_view isFirstResponder];
}

// Note: this implicitly loads the view if it hasn't been loaded yet.
- (BOOL)becomeFirstResponder
{
  ASDisplayNodeAssertMainThread();
  return !self.layerBacked && [self canBecomeFirstResponder] && [self.view becomeFirstResponder];
}

- (BOOL)resignFirstResponder
{
  ASDisplayNodeAssertMainThread();
  return !self.layerBacked && [self canResignFirstResponder] && [_view resignFirstResponder];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
  ASDisplayNodeAssertMainThread();
  return !self.layerBacked && [self.view canPerformAction:action withSender:sender];
}

- (CGFloat)alpha
{
  _bridge_prologue;
  return _getFromPendingViewState(alpha);
}

- (void)setAlpha:(CGFloat)newAlpha
{
  _bridge_prologue;
  _setToViewOrLayer(opacity, newAlpha, alpha, newAlpha);
}

- (CGFloat)cornerRadius
{
  _bridge_prologue;
  return _getFromPendingViewState(cornerRadius);
}

- (void)setCornerRadius:(CGFloat)newCornerRadius
{
  _bridge_prologue;
  _setToLayer(cornerRadius, newCornerRadius);
}

- (CGFloat)contentsScale
{
  _bridge_prologue;
  return _getFromPendingViewState(contentsScale);
}

- (void)setContentsScale:(CGFloat)newContentsScale
{
  _bridge_prologue;
  _setToLayer(contentsScale, newContentsScale);
}

- (CGRect)bounds
{
  _bridge_prologue;
  return _getFromPendingViewState(bounds);
}

- (void)setBounds:(CGRect)newBounds
{
  _bridge_prologue;
  _setToViewOrLayer(bounds, newBounds, bounds, newBounds);
}

- (CGRect)frame
{
  _bridge_prologue;

  // Frame is only defined when transform is identity.
#if DEBUG
  // Checking if the transform is identity is expensive, so disable when unnecessary. We have assertions on in Release, so DEBUG is the only way I know of.
  ASDisplayNodeAssert(CATransform3DIsIdentity(self.transform), @"-[ASDisplayNode frame] - self.transform must be identity in order to use the frame property.  (From Apple's UIView documentation: If the transform property is not the identity transform, the value of this property is undefined and therefore should be ignored.)");
#endif

  CGPoint position = self.position;
  CGRect bounds = self.bounds;
  CGPoint anchorPoint = self.anchorPoint;
  CGPoint origin = CGPointMake(position.x - bounds.size.width * anchorPoint.x,
                               position.y - bounds.size.height * anchorPoint.y);
  return CGRectMake(origin.x, origin.y, bounds.size.width, bounds.size.height);
}

- (void)setFrame:(CGRect)rect
{
  _bridge_prologue;

  if (_flags.synchronous && !_flags.layerBacked) {
    // For classes like ASTableNode, ASCollectionNode, ASScrollNode and similar - make sure UIView gets setFrame:
    
    // Frame is only defined when transform is identity because we explicitly diverge from CALayer behavior and define frame without transform
#if DEBUG
    // Checking if the transform is identity is expensive, so disable when unnecessary. We have assertions on in Release, so DEBUG is the only way I know of.
    ASDisplayNodeAssert(CATransform3DIsIdentity(self.transform), @"-[ASDisplayNode setFrame:] - self.transform must be identity in order to set the frame property.  (From Apple's UIView documentation: If the transform property is not the identity transform, the value of this property is undefined and therefore should be ignored.)");
#endif
    _setToViewOnly(frame, rect);
  } else {
    // This is by far the common case / hot path.
    [self __setSafeFrame:rect];
  }
}

/**
 * Sets a new frame to this node by changing its bounds and position. This method can be safely called even if
 * the transform is a non-identity transform, because bounds and position can be set instead of frame.
 * This is NOT called for synchronous nodes (wrapping regular views), which may rely on a [UIView setFrame:] call.
 * A notable example of the latter is UITableView, which won't resize its internal container if only layer bounds are set.
 */
- (void)__setSafeFrame:(CGRect)rect
{
  ASDisplayNodeAssertThreadAffinity(self);
  ASDN::MutexLocker l(_propertyLock);
  
  BOOL useLayer = (_layer && ASDisplayNodeThreadIsMain());
  
  CGPoint origin      = (useLayer ? _layer.bounds.origin : self.bounds.origin);
  CGPoint anchorPoint = (useLayer ? _layer.anchorPoint   : self.anchorPoint);
  
  CGRect  bounds      = (CGRect){ origin, rect.size };
  CGPoint position    = CGPointMake(rect.origin.x + rect.size.width * anchorPoint.x,
                                    rect.origin.y + rect.size.height * anchorPoint.y);
  
  if (useLayer) {
    _layer.bounds = bounds;
    _layer.position = position;
  } else {
    self.bounds = bounds;
    self.position = position;
  }
}

- (void)setNeedsDisplay
{
  _bridge_prologue;

  if (_hierarchyState & ASHierarchyStateRasterized) {
    ASPerformBlockOnMainThread(^{
      // The below operation must be performed on the main thread to ensure against an extremely rare deadlock, where a parent node
      // begins materializing the view / layer heirarchy (locking itself or a descendant) while this node walks up
      // the tree and requires locking that node to access .shouldRasterizeDescendants.
      // For this reason, this method should be avoided when possible.  Use _hierarchyState & ASHierarchyStateRasterized.
      ASDisplayNodeAssertMainThread();
      ASDisplayNode *rasterizedContainerNode = self.supernode;
      while (rasterizedContainerNode) {
        if (rasterizedContainerNode.shouldRasterizeDescendants) {
          break;
        }
        rasterizedContainerNode = rasterizedContainerNode.supernode;
      }
      [rasterizedContainerNode setNeedsDisplay];
    });
  } else {
    // If not rasterized (and therefore we certainly have a view or layer),
    // Send the message to the view/layer first, as scheduleNodeForDisplay may call -displayIfNeeded.
    // Wrapped / synchronous nodes created with initWithView/LayerBlock: do not need scheduleNodeForDisplay,
    // as they don't need to display in the working range at all - since at all times onscreen, one
    // -setNeedsDisplay to the CALayer will result in a synchronous display in the next frame.

    _messageToViewOrLayer(setNeedsDisplay);

    BOOL nowDisplay = ASInterfaceStateIncludesDisplay(_interfaceState);
    // FIXME: This should not need to recursively display, so create a non-recursive variant.
    // The semantics of setNeedsDisplay (as defined by CALayer behavior) are not recursive.
    if (_layer && !_flags.synchronous && nowDisplay && [self __implementsDisplay]) {
      [ASDisplayNode scheduleNodeForRecursiveDisplay:self];
    }
  }
}

- (void)setNeedsLayout
{
  _bridge_prologue;
  [self __setNeedsLayout];
  _messageToViewOrLayer(setNeedsLayout);
}

- (BOOL)isOpaque
{
  _bridge_prologue;
  return _getFromPendingViewState(opaque);
}

- (void)setOpaque:(BOOL)newOpaque
{
  _bridge_prologue;
  _setToViewOrLayer(opaque, newOpaque, opaque, newOpaque);

  // TODO: Mark as needs display if value changed?
}

- (BOOL)isUserInteractionEnabled
{
  _bridge_prologue;
  if (_flags.layerBacked) return NO;
  return _getFromPendingViewState(userInteractionEnabled);
}

- (void)setUserInteractionEnabled:(BOOL)enabled
{
  _bridge_prologue;
  _setToViewOnly(userInteractionEnabled, enabled);
}
#if TARGET_OS_IOS
- (BOOL)isExclusiveTouch
{
  _bridge_prologue;
  return _getFromPendingViewState(exclusiveTouch);
}

- (void)setExclusiveTouch:(BOOL)exclusiveTouch
{
  _bridge_prologue;
  _setToViewOnly(exclusiveTouch, exclusiveTouch);
}
#endif
- (BOOL)clipsToBounds
{
  _bridge_prologue;
  return _getFromPendingViewState(clipsToBounds);
}

- (void)setClipsToBounds:(BOOL)clips
{
  _bridge_prologue;
  _setToViewOrLayer(masksToBounds, clips, clipsToBounds, clips);
}

- (CGPoint)anchorPoint
{
  _bridge_prologue;
  return _getFromPendingViewState(anchorPoint);
}

- (void)setAnchorPoint:(CGPoint)newAnchorPoint
{
  _bridge_prologue;
  _setToLayer(anchorPoint, newAnchorPoint);
}

- (CGPoint)position
{
  _bridge_prologue;
  return _getFromPendingViewState(position);
}

- (void)setPosition:(CGPoint)newPosition
{
  _bridge_prologue;
  _setToLayer(position, newPosition);
}

- (CGFloat)zPosition
{
  _bridge_prologue;
  return _getFromPendingViewState(zPosition);
}

- (void)setZPosition:(CGFloat)newPosition
{
  _bridge_prologue;
  _setToLayer(zPosition, newPosition);
}

- (CATransform3D)transform
{
  _bridge_prologue;
  return _getFromPendingViewState(transform);
}

- (void)setTransform:(CATransform3D)newTransform
{
  _bridge_prologue;
  _setToLayer(transform, newTransform);
}

- (CATransform3D)subnodeTransform
{
  _bridge_prologue;
  return _getFromPendingViewState(sublayerTransform);
}

- (void)setSubnodeTransform:(CATransform3D)newSubnodeTransform
{
  _bridge_prologue;
  _setToLayer(sublayerTransform, newSubnodeTransform);
}

- (id)contents
{
  _bridge_prologue;
  return _getFromPendingViewState(contents);
}

- (void)setContents:(id)newContents
{
  _bridge_prologue;
  _setToLayer(contents, newContents);
}

- (BOOL)isHidden
{
  _bridge_prologue;
  return _getFromPendingViewState(hidden);
}

- (void)setHidden:(BOOL)flag
{
  _bridge_prologue;
  _setToViewOrLayer(hidden, flag, hidden, flag);
}

- (BOOL)needsDisplayOnBoundsChange
{
  _bridge_prologue;
  return _getFromPendingViewState(needsDisplayOnBoundsChange);
}

- (void)setNeedsDisplayOnBoundsChange:(BOOL)flag
{
  _bridge_prologue;
  _setToLayer(needsDisplayOnBoundsChange, flag);
}

- (BOOL)autoresizesSubviews
{
  _bridge_prologue;
  ASDisplayNodeAssert(!_flags.layerBacked, @"Danger: this property is undefined on layer-backed nodes.");
  return _getFromPendingViewState(autoresizesSubviews);
}

- (void)setAutoresizesSubviews:(BOOL)flag
{
  _bridge_prologue;
  ASDisplayNodeAssert(!_flags.layerBacked, @"Danger: this property is undefined on layer-backed nodes.");
  _setToViewOnly(autoresizesSubviews, flag);
}

- (UIViewAutoresizing)autoresizingMask
{
  _bridge_prologue;
  ASDisplayNodeAssert(!_flags.layerBacked, @"Danger: this property is undefined on layer-backed nodes.");
  return _getFromPendingViewState(autoresizingMask);
}

- (void)setAutoresizingMask:(UIViewAutoresizing)mask
{
  _bridge_prologue;
  ASDisplayNodeAssert(!_flags.layerBacked, @"Danger: this property is undefined on layer-backed nodes.");
  _setToViewOnly(autoresizingMask, mask);
}

- (UIViewContentMode)contentMode
{
  _bridge_prologue;
  if (__loaded) {
    if (_flags.layerBacked) {
      return ASDisplayNodeUIContentModeFromCAContentsGravity(_layer.contentsGravity);
    } else {
      return _view.contentMode;
    }
  } else {
    return self.pendingViewState.contentMode;
  }
}

- (void)setContentMode:(UIViewContentMode)contentMode
{
  _bridge_prologue;
  if (__loaded) {
    if (_flags.layerBacked) {
      _layer.contentsGravity = ASDisplayNodeCAContentsGravityFromUIContentMode(contentMode);
    } else {
      _view.contentMode = contentMode;
    }
  } else {
    self.pendingViewState.contentMode = contentMode;
  }
}

- (UIColor *)backgroundColor
{
  _bridge_prologue;
  return [UIColor colorWithCGColor:_getFromPendingViewState(backgroundColor)];
}

- (void)setBackgroundColor:(UIColor *)newBackgroundColor
{
  UIColor *prevBackgroundColor = self.backgroundColor;

  _bridge_prologue;
  _setToLayer(backgroundColor, newBackgroundColor.CGColor);

  // Note: This check assumes that the colors are within the same color space.
  if (!ASObjectIsEqual(prevBackgroundColor, newBackgroundColor)) {
    [self setNeedsDisplay];
  }
}

- (UIColor *)tintColor
{
    _bridge_prologue;
    ASDisplayNodeAssert(!_flags.layerBacked, @"Danger: this property is undefined on layer-backed nodes.");
    return _getFromPendingViewState(tintColor);
}

- (void)setTintColor:(UIColor *)color
{
    _bridge_prologue;
    ASDisplayNodeAssert(!_flags.layerBacked, @"Danger: this property is undefined on layer-backed nodes.");
    _setToViewOnly(tintColor, color);
}

- (void)tintColorDidChange
{
    // ignore this, allow subclasses to be notified
}

- (CGColorRef)shadowColor
{
  _bridge_prologue;
  return _getFromPendingViewState(shadowColor);
}

- (void)setShadowColor:(CGColorRef)colorValue
{
  _bridge_prologue;
  _setToLayer(shadowColor, colorValue);
}

- (CGFloat)shadowOpacity
{
  _bridge_prologue;
  return _getFromPendingViewState(shadowOpacity);
}

- (void)setShadowOpacity:(CGFloat)opacity
{
  _bridge_prologue;
  _setToLayer(shadowOpacity, opacity);
}

- (CGSize)shadowOffset
{
  _bridge_prologue;
  return _getFromPendingViewState(shadowOffset);
}

- (void)setShadowOffset:(CGSize)offset
{
  _bridge_prologue;
  _setToLayer(shadowOffset, offset);
}

- (CGFloat)shadowRadius
{
  _bridge_prologue;
  return _getFromPendingViewState(shadowRadius);
}

- (void)setShadowRadius:(CGFloat)radius
{
  _bridge_prologue;
  _setToLayer(shadowRadius, radius);
}

- (CGFloat)borderWidth
{
  _bridge_prologue;
  return _getFromPendingViewState(borderWidth);
}

- (void)setBorderWidth:(CGFloat)width
{
  _bridge_prologue;
  _setToLayer(borderWidth, width);
}

- (CGColorRef)borderColor
{
  _bridge_prologue;
  return _getFromPendingViewState(borderColor);
}

- (void)setBorderColor:(CGColorRef)colorValue
{
  _bridge_prologue;
  _setToLayer(borderColor, colorValue);
}

- (BOOL)allowsEdgeAntialiasing
{
  _bridge_prologue;
  return _getFromPendingViewState(allowsEdgeAntialiasing);
}

- (void)setAllowsEdgeAntialiasing:(BOOL)allowsEdgeAntialiasing
{
  _bridge_prologue;
  _setToLayer(allowsEdgeAntialiasing, allowsEdgeAntialiasing);
}

- (unsigned int)edgeAntialiasingMask
{
  _bridge_prologue;
  return _getFromPendingViewState(edgeAntialiasingMask);
}

- (void)setEdgeAntialiasingMask:(unsigned int)edgeAntialiasingMask
{
  _bridge_prologue;
  _setToLayer(edgeAntialiasingMask, edgeAntialiasingMask);
}

- (BOOL)isAccessibilityElement
{
  _bridge_prologue;
  return _getFromPendingViewState(isAccessibilityElement);
}

- (void)setIsAccessibilityElement:(BOOL)isAccessibilityElement
{
  _bridge_prologue;
  _setToViewOnly(isAccessibilityElement, isAccessibilityElement);
}

- (NSString *)accessibilityLabel
{
  _bridge_prologue;
  return _getFromPendingViewState(accessibilityLabel);
}

- (void)setAccessibilityLabel:(NSString *)accessibilityLabel
{
  _bridge_prologue;
  _setToViewOnly(accessibilityLabel, accessibilityLabel);
}

- (NSString *)accessibilityHint
{
  _bridge_prologue;
  return _getFromPendingViewState(accessibilityHint);
}

- (void)setAccessibilityHint:(NSString *)accessibilityHint
{
  _bridge_prologue;
  _setToViewOnly(accessibilityHint, accessibilityHint);
}

- (NSString *)accessibilityValue
{
  _bridge_prologue;
  return _getFromPendingViewState(accessibilityValue);
}

- (void)setAccessibilityValue:(NSString *)accessibilityValue
{
  _bridge_prologue;
  _setToViewOnly(accessibilityValue, accessibilityValue);
}

- (UIAccessibilityTraits)accessibilityTraits
{
  _bridge_prologue;
  return _getFromPendingViewState(accessibilityTraits);
}

- (void)setAccessibilityTraits:(UIAccessibilityTraits)accessibilityTraits
{
  _bridge_prologue;
  _setToViewOnly(accessibilityTraits, accessibilityTraits);
}

- (CGRect)accessibilityFrame
{
  _bridge_prologue;
  return _getFromPendingViewState(accessibilityFrame);
}

- (void)setAccessibilityFrame:(CGRect)accessibilityFrame
{
  _bridge_prologue;
  _setToViewOnly(accessibilityFrame, accessibilityFrame);
}

- (NSString *)accessibilityLanguage
{
  _bridge_prologue;
  return _getFromPendingViewState(accessibilityLanguage);
}

- (void)setAccessibilityLanguage:(NSString *)accessibilityLanguage
{
  _bridge_prologue;
  _setToViewOnly(accessibilityLanguage, accessibilityLanguage);
}

- (BOOL)accessibilityElementsHidden
{
  _bridge_prologue;
  return _getFromPendingViewState(accessibilityElementsHidden);
}

- (void)setAccessibilityElementsHidden:(BOOL)accessibilityElementsHidden
{
  _bridge_prologue;
  _setToViewOnly(accessibilityElementsHidden, accessibilityElementsHidden);
}

- (BOOL)accessibilityViewIsModal
{
  _bridge_prologue;
  return _getFromPendingViewState(accessibilityViewIsModal);
}

- (void)setAccessibilityViewIsModal:(BOOL)accessibilityViewIsModal
{
  _bridge_prologue;
  _setToViewOnly(accessibilityViewIsModal, accessibilityViewIsModal);
}

- (BOOL)shouldGroupAccessibilityChildren
{
  _bridge_prologue;
  return _getFromPendingViewState(shouldGroupAccessibilityChildren);
}

- (void)setShouldGroupAccessibilityChildren:(BOOL)shouldGroupAccessibilityChildren
{
  _bridge_prologue;
  _setToViewOnly(shouldGroupAccessibilityChildren, shouldGroupAccessibilityChildren);
}

- (NSString *)accessibilityIdentifier
{
  _bridge_prologue;
  return _getFromPendingViewState(accessibilityIdentifier);
}

- (void)setAccessibilityIdentifier:(NSString *)accessibilityIdentifier
{
  _bridge_prologue;
  _setToViewOnly(accessibilityIdentifier, accessibilityIdentifier);
}

@end


@implementation ASDisplayNode (ASAsyncTransactionContainer)

- (BOOL)asyncdisplaykit_isAsyncTransactionContainer
{
  _bridge_prologue;
  return _getFromPendingViewState(asyncdisplaykit_isAsyncTransactionContainer);
}

- (void)asyncdisplaykit_setAsyncTransactionContainer:(BOOL)asyncTransactionContainer
{
  _bridge_prologue;
  _setToViewOrLayer(asyncdisplaykit_asyncTransactionContainer, asyncTransactionContainer, asyncdisplaykit_asyncTransactionContainer, asyncTransactionContainer);
}

- (ASAsyncTransactionContainerState)asyncdisplaykit_asyncTransactionContainerState
{
  ASDisplayNodeAssertMainThread();
  return [_layer asyncdisplaykit_asyncTransactionContainerState];
}

- (void)asyncdisplaykit_cancelAsyncTransactions
{
  ASDisplayNodeAssertMainThread();
  [_layer asyncdisplaykit_cancelAsyncTransactions];
}

- (void)asyncdisplaykit_asyncTransactionContainerStateDidChange
{
}

@end
