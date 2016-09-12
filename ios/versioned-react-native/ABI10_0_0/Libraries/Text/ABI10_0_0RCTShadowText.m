/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "ABI10_0_0RCTShadowText.h"

#import "ABI10_0_0RCTAccessibilityManager.h"
#import "ABI10_0_0RCTBridge.h"
#import "ABI10_0_0RCTConvert.h"
#import "ABI10_0_0RCTFont.h"
#import "ABI10_0_0RCTLog.h"
#import "ABI10_0_0RCTShadowRawText.h"
#import "ABI10_0_0RCTText.h"
#import "ABI10_0_0RCTTextView.h"
#import "ABI10_0_0RCTUIManager.h"
#import "ABI10_0_0RCTUtils.h"

NSString *const ABI10_0_0RCTShadowViewAttributeName = @"ABI10_0_0RCTShadowViewAttributeName";
NSString *const ABI10_0_0RCTIsHighlightedAttributeName = @"IsHighlightedAttributeName";
NSString *const ABI10_0_0RCTReactABI10_0_0TagAttributeName = @"ReactABI10_0_0TagAttributeName";

CGFloat const ABI10_0_0RCTTextAutoSizeDefaultMinimumFontScale       = 0.5f;
CGFloat const ABI10_0_0RCTTextAutoSizeWidthErrorMargin              = 0.05f;
CGFloat const ABI10_0_0RCTTextAutoSizeHeightErrorMargin             = 0.025f;
CGFloat const ABI10_0_0RCTTextAutoSizeGranularity                   = 0.001f;

@implementation ABI10_0_0RCTShadowText
{
  NSTextStorage *_cachedTextStorage;
  CGFloat _cachedTextStorageWidth;
  CGFloat _cachedTextStorageWidthMode;
  NSAttributedString *_cachedAttributedString;
  CGFloat _effectiveLetterSpacing;
}

static ABI10_0_0CSSSize ABI10_0_0RCTMeasure(void *context, float width, ABI10_0_0CSSMeasureMode widthMode, float height, ABI10_0_0CSSMeasureMode heightMode)
{
  ABI10_0_0RCTShadowText *shadowText = (__bridge ABI10_0_0RCTShadowText *)context;
  NSTextStorage *textStorage = [shadowText buildTextStorageForWidth:width widthMode:widthMode];
  [shadowText calculateTextFrame:textStorage];
  NSLayoutManager *layoutManager = textStorage.layoutManagers.firstObject;
  NSTextContainer *textContainer = layoutManager.textContainers.firstObject;
  CGSize computedSize = [layoutManager usedRectForTextContainer:textContainer].size;

  ABI10_0_0CSSSize result;
  result.width = ABI10_0_0RCTCeilPixelValue(computedSize.width);
  if (shadowText->_effectiveLetterSpacing < 0) {
    result.width -= shadowText->_effectiveLetterSpacing;
  }
  result.height = ABI10_0_0RCTCeilPixelValue(computedSize.height);
  return result;
}

- (instancetype)init
{
  if ((self = [super init])) {
    _fontSize = NAN;
    _letterSpacing = NAN;
    _isHighlighted = NO;
    _textDecorationStyle = NSUnderlineStyleSingle;
    _opacity = 1.0;
    _cachedTextStorageWidth = -1;
    _cachedTextStorageWidthMode = -1;
    _fontSizeMultiplier = 1.0;
    ABI10_0_0CSSNodeSetMeasureFunc(self.cssNode, ABI10_0_0RCTMeasure);
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeMultiplierDidChange:)
                                                 name:ABI10_0_0RCTUIManagerWillUpdateViewsDueToContentSizeMultiplierChangeNotification
                                               object:nil];
  }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSString *)description
{
  NSString *superDescription = super.description;
  return [[superDescription substringToIndex:superDescription.length - 1] stringByAppendingFormat:@"; text: %@>", [self attributedString].string];
}

- (BOOL)isABI10_0_0CSSLeafNode
{
  return YES;
}

- (void)contentSizeMultiplierDidChange:(NSNotification *)note
{
  ABI10_0_0CSSNodeMarkDirty(self.cssNode);
  [self dirtyText];
}

- (NSDictionary<NSString *, id> *)processUpdatedProperties:(NSMutableSet<ABI10_0_0RCTApplierBlock> *)applierBlocks
                                          parentProperties:(NSDictionary<NSString *, id> *)parentProperties
{
  if ([[self ReactABI10_0_0Superview] isKindOfClass:[ABI10_0_0RCTShadowText class]]) {
    return parentProperties;
  }

  parentProperties = [super processUpdatedProperties:applierBlocks
                                    parentProperties:parentProperties];

  UIEdgeInsets padding = self.paddingAsInsets;
  CGFloat width = self.frame.size.width - (padding.left + padding.right);


  NSNumber *parentTag = [[self ReactABI10_0_0Superview] ReactABI10_0_0Tag];
  NSTextStorage *textStorage = [self buildTextStorageForWidth:width widthMode:ABI10_0_0CSSMeasureModeExactly];
  CGRect textFrame = [self calculateTextFrame:textStorage];
  [applierBlocks addObject:^(NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    ABI10_0_0RCTText *view = (ABI10_0_0RCTText *)viewRegistry[self.ReactABI10_0_0Tag];
    view.textFrame = textFrame;
    view.textStorage = textStorage;

    /**
     * NOTE: this logic is included to support rich text editing inside multiline
     * `<TextInput>` controls. It is required in order to ensure that the
     * textStorage (aka attributed string) is copied over from the ABI10_0_0RCTShadowText
     * to the ABI10_0_0RCTText view in time to be used to update the editable text content.
     * TODO: we should establish a delegate relationship betweeen ABI10_0_0RCTTextView
     * and its contaned ABI10_0_0RCTText element when they get inserted and get rid of this
     */
    UIView *parentView = viewRegistry[parentTag];
    if ([parentView respondsToSelector:@selector(performTextUpdate)]) {
      [(ABI10_0_0RCTTextView *)parentView performTextUpdate];
    }
  }];

  return parentProperties;
}

- (void)applyLayoutNode:(ABI10_0_0CSSNodeRef)node
      viewsWithNewFrame:(NSMutableSet<ABI10_0_0RCTShadowView *> *)viewsWithNewFrame
       absolutePosition:(CGPoint)absolutePosition
{
  [super applyLayoutNode:node viewsWithNewFrame:viewsWithNewFrame absolutePosition:absolutePosition];
  [self dirtyPropagation];
}

- (void)applyLayoutToChildren:(ABI10_0_0CSSNodeRef)node
            viewsWithNewFrame:(NSMutableSet<ABI10_0_0RCTShadowView *> *)viewsWithNewFrame
             absolutePosition:(CGPoint)absolutePosition
{
  // Run layout on subviews.
  NSTextStorage *textStorage = [self buildTextStorageForWidth:self.frame.size.width widthMode:ABI10_0_0CSSMeasureModeExactly];
  NSLayoutManager *layoutManager = textStorage.layoutManagers.firstObject;
  NSTextContainer *textContainer = layoutManager.textContainers.firstObject;
  NSRange glyphRange = [layoutManager glyphRangeForTextContainer:textContainer];
  NSRange characterRange = [layoutManager characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];
  [layoutManager.textStorage enumerateAttribute:ABI10_0_0RCTShadowViewAttributeName inRange:characterRange options:0 usingBlock:^(ABI10_0_0RCTShadowView *child, NSRange range, BOOL *_) {
    if (child) {
      ABI10_0_0CSSNodeRef childNode = child.cssNode;
      float width = ABI10_0_0CSSNodeStyleGetWidth(childNode);
      float height = ABI10_0_0CSSNodeStyleGetHeight(childNode);
      if (ABI10_0_0CSSValueIsUndefined(width) || ABI10_0_0CSSValueIsUndefined(height)) {
        ABI10_0_0RCTLogError(@"Views nested within a <Text> must have a width and height");
      }
      UIFont *font = [textStorage attribute:NSFontAttributeName atIndex:range.location effectiveRange:nil];
      CGRect glyphRect = [layoutManager boundingRectForGlyphRange:range inTextContainer:textContainer];
      CGRect childFrame = {{
        ABI10_0_0RCTRoundPixelValue(glyphRect.origin.x),
        ABI10_0_0RCTRoundPixelValue(glyphRect.origin.y + glyphRect.size.height - height + font.descender)
      }, {
        ABI10_0_0RCTRoundPixelValue(width),
        ABI10_0_0RCTRoundPixelValue(height)
      }};

      NSRange truncatedGlyphRange = [layoutManager truncatedGlyphRangeInLineFragmentForGlyphAtIndex:range.location];
      BOOL childIsTruncated = NSIntersectionRange(range, truncatedGlyphRange).length != 0;

      [child collectUpdatedFrames:viewsWithNewFrame
                        withFrame:childFrame
                           hidden:childIsTruncated
                 absolutePosition:absolutePosition];
    }
  }];
}

- (NSTextStorage *)buildTextStorageForWidth:(CGFloat)width widthMode:(ABI10_0_0CSSMeasureMode)widthMode
{
  if (_cachedTextStorage && width == _cachedTextStorageWidth && widthMode == _cachedTextStorageWidthMode) {
    return _cachedTextStorage;
  }

  NSLayoutManager *layoutManager = [NSLayoutManager new];

  NSTextStorage *textStorage = [[NSTextStorage alloc] initWithAttributedString:self.attributedString];
  [textStorage addLayoutManager:layoutManager];

  NSTextContainer *textContainer = [NSTextContainer new];
  textContainer.lineFragmentPadding = 0.0;

  if (_numberOfLines > 0) {
    textContainer.lineBreakMode = _ellipsizeMode;
  } else {
    textContainer.lineBreakMode = NSLineBreakByClipping;
  }

  textContainer.maximumNumberOfLines = _numberOfLines;
  textContainer.size = (CGSize){widthMode == ABI10_0_0CSSMeasureModeUndefined ? CGFLOAT_MAX : width, CGFLOAT_MAX};

  [layoutManager addTextContainer:textContainer];
  [layoutManager ensureLayoutForTextContainer:textContainer];

  _cachedTextStorageWidth = width;
  _cachedTextStorageWidthMode = widthMode;
  _cachedTextStorage = textStorage;

  return textStorage;
}

- (void)dirtyText
{
  [super dirtyText];
  _cachedTextStorage = nil;
}

- (void)recomputeText
{
  [self attributedString];
  [self setTextComputed];
  [self dirtyPropagation];
}

- (NSAttributedString *)attributedString
{
  return [self _attributedStringWithFontFamily:nil
                                      fontSize:nil
                                    fontWeight:nil
                                     fontStyle:nil
                                 letterSpacing:nil
                            useBackgroundColor:NO
                               foregroundColor:self.color ?: [UIColor blackColor]
                               backgroundColor:self.backgroundColor
                                       opacity:self.opacity];
}

- (NSAttributedString *)_attributedStringWithFontFamily:(NSString *)fontFamily
                                               fontSize:(NSNumber *)fontSize
                                             fontWeight:(NSString *)fontWeight
                                              fontStyle:(NSString *)fontStyle
                                          letterSpacing:(NSNumber *)letterSpacing
                                     useBackgroundColor:(BOOL)useBackgroundColor
                                        foregroundColor:(UIColor *)foregroundColor
                                        backgroundColor:(UIColor *)backgroundColor
                                                opacity:(CGFloat)opacity
{
  if (![self isTextDirty] && _cachedAttributedString) {
    return _cachedAttributedString;
  }

  if (_fontSize && !isnan(_fontSize)) {
    fontSize = @(_fontSize);
  }
  if (_fontWeight) {
    fontWeight = _fontWeight;
  }
  if (_fontStyle) {
    fontStyle = _fontStyle;
  }
  if (_fontFamily) {
    fontFamily = _fontFamily;
  }
  if (!isnan(_letterSpacing)) {
    letterSpacing = @(_letterSpacing);
  }

  _effectiveLetterSpacing = letterSpacing.doubleValue;

  UIFont *font = [ABI10_0_0RCTFont updateFont:nil
                          withFamily:fontFamily
                                size:fontSize
                              weight:fontWeight
                               style:fontStyle
                             variant:_fontVariant
                     scaleMultiplier:_allowFontScaling ? _fontSizeMultiplier : 1.0];

  CGFloat heightOfTallestSubview = 0.0;
  NSMutableAttributedString *attributedString = [NSMutableAttributedString new];
  for (ABI10_0_0RCTShadowView *child in [self ReactABI10_0_0Subviews]) {
    if ([child isKindOfClass:[ABI10_0_0RCTShadowText class]]) {
      ABI10_0_0RCTShadowText *shadowText = (ABI10_0_0RCTShadowText *)child;
      [attributedString appendAttributedString:
       [shadowText _attributedStringWithFontFamily:fontFamily
                                          fontSize:fontSize
                                        fontWeight:fontWeight
                                         fontStyle:fontStyle
                                     letterSpacing:letterSpacing
                                useBackgroundColor:YES
                                   foregroundColor:shadowText.color ?: foregroundColor
                                   backgroundColor:shadowText.backgroundColor ?: backgroundColor
                                           opacity:opacity * shadowText.opacity]];
      [child setTextComputed];
    } else if ([child isKindOfClass:[ABI10_0_0RCTShadowRawText class]]) {
      ABI10_0_0RCTShadowRawText *shadowRawText = (ABI10_0_0RCTShadowRawText *)child;
      [attributedString appendAttributedString:[[NSAttributedString alloc] initWithString:shadowRawText.text ?: @""]];
      [child setTextComputed];
    } else {
      float width = ABI10_0_0CSSNodeStyleGetWidth(child.cssNode);
      float height = ABI10_0_0CSSNodeStyleGetHeight(child.cssNode);
      if (ABI10_0_0CSSValueIsUndefined(width) || ABI10_0_0CSSValueIsUndefined(height)) {
        ABI10_0_0RCTLogError(@"Views nested within a <Text> must have a width and height");
      }
      NSTextAttachment *attachment = [NSTextAttachment new];
      attachment.bounds = (CGRect){CGPointZero, {width, height}};
      NSMutableAttributedString *attachmentString = [NSMutableAttributedString new];
      [attachmentString appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
      [attachmentString addAttribute:ABI10_0_0RCTShadowViewAttributeName value:child range:(NSRange){0, attachmentString.length}];
      [attributedString appendAttributedString:attachmentString];
      if (height > heightOfTallestSubview) {
        heightOfTallestSubview = height;
      }
      // Don't call setTextComputed on this child. ABI10_0_0RCTTextManager takes care of
      // processing inline UIViews.
    }
  }

  [self _addAttribute:NSForegroundColorAttributeName
            withValue:[foregroundColor colorWithAlphaComponent:CGColorGetAlpha(foregroundColor.CGColor) * opacity]
   toAttributedString:attributedString];

  if (_isHighlighted) {
    [self _addAttribute:ABI10_0_0RCTIsHighlightedAttributeName withValue:@YES toAttributedString:attributedString];
  }
  if (useBackgroundColor && backgroundColor) {
    [self _addAttribute:NSBackgroundColorAttributeName
              withValue:[backgroundColor colorWithAlphaComponent:CGColorGetAlpha(backgroundColor.CGColor) * opacity]
     toAttributedString:attributedString];
  }

  [self _addAttribute:NSFontAttributeName withValue:font toAttributedString:attributedString];
  [self _addAttribute:NSKernAttributeName withValue:letterSpacing toAttributedString:attributedString];
  [self _addAttribute:ABI10_0_0RCTReactABI10_0_0TagAttributeName withValue:self.ReactABI10_0_0Tag toAttributedString:attributedString];
  [self _setParagraphStyleOnAttributedString:attributedString
                              fontLineHeight:font.lineHeight
                      heightOfTallestSubview:heightOfTallestSubview];

  // create a non-mutable attributedString for use by the Text system which avoids copies down the line
  _cachedAttributedString = [[NSAttributedString alloc] initWithAttributedString:attributedString];
  ABI10_0_0CSSNodeMarkDirty(self.cssNode);

  return _cachedAttributedString;
}

- (void)_addAttribute:(NSString *)attribute withValue:(id)attributeValue toAttributedString:(NSMutableAttributedString *)attributedString
{
  [attributedString enumerateAttribute:attribute inRange:NSMakeRange(0, attributedString.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
    if (!value && attributeValue) {
      [attributedString addAttribute:attribute value:attributeValue range:range];
    }
  }];
}

/*
 * LineHeight works the same way line-height works in the web: if children and self have
 * varying lineHeights, we simply take the max.
 */
- (void)_setParagraphStyleOnAttributedString:(NSMutableAttributedString *)attributedString
                                    fontLineHeight:(CGFloat)fontLineHeight
                      heightOfTallestSubview:(CGFloat)heightOfTallestSubview
{
  // check if we have lineHeight set on self
  __block BOOL hasParagraphStyle = NO;
  if (_lineHeight || _textAlign) {
    hasParagraphStyle = YES;
  }

  __block float newLineHeight = _lineHeight ?: 0.0;

  CGFloat fontSizeMultiplier = _allowFontScaling ? _fontSizeMultiplier : 1.0;

  // check for lineHeight on each of our children, update the max as we go (in self.lineHeight)
  [attributedString enumerateAttribute:NSParagraphStyleAttributeName inRange:(NSRange){0, attributedString.length} options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
    if (value) {
      NSParagraphStyle *paragraphStyle = (NSParagraphStyle *)value;
      CGFloat maximumLineHeight = round(paragraphStyle.maximumLineHeight / fontSizeMultiplier);
      if (maximumLineHeight > newLineHeight) {
        newLineHeight = maximumLineHeight;
      }
      hasParagraphStyle = YES;
    }
  }];

  if (self.lineHeight != newLineHeight) {
    self.lineHeight = newLineHeight;
  }

  NSTextAlignment newTextAlign = _textAlign ?: NSTextAlignmentNatural;

  // The part below is to address textAlign for RTL language before setting paragraph style
  // Since we can't get layout directly because this logic is currently run just before layout is calculatede
  // We will climb up to the first node which style has been setted as non-inherit
  if (newTextAlign == NSTextAlignmentRight || newTextAlign == NSTextAlignmentLeft) {
    ABI10_0_0RCTShadowView *view = self;
    while (view != nil && ABI10_0_0CSSNodeStyleGetDirection(view.cssNode) == ABI10_0_0CSSDirectionInherit) {
      view = [view ReactABI10_0_0Superview];
    }
    if (view != nil && ABI10_0_0CSSNodeStyleGetDirection(view.cssNode) == ABI10_0_0CSSDirectionRTL) {
      if (newTextAlign == NSTextAlignmentRight) {
        newTextAlign = NSTextAlignmentLeft;
      } else if (newTextAlign == NSTextAlignmentLeft) {
        newTextAlign = NSTextAlignmentRight;
      }
    }
  }

  if (self.textAlign != newTextAlign) {
    self.textAlign = newTextAlign;
  }
  NSWritingDirection newWritingDirection = _writingDirection ?: NSWritingDirectionNatural;
  if (self.writingDirection != newWritingDirection) {
    self.writingDirection = newWritingDirection;
  }

  // if we found anything, set it :D
  if (hasParagraphStyle) {
    NSMutableParagraphStyle *paragraphStyle = [NSMutableParagraphStyle new];
    paragraphStyle.alignment = _textAlign;
    paragraphStyle.baseWritingDirection = _writingDirection;
    CGFloat lineHeight = round(_lineHeight * fontSizeMultiplier);
    if (heightOfTallestSubview > lineHeight) {
      lineHeight = ceilf(heightOfTallestSubview);
    }
    paragraphStyle.minimumLineHeight = lineHeight;
    paragraphStyle.maximumLineHeight = lineHeight;
    [attributedString addAttribute:NSParagraphStyleAttributeName
                             value:paragraphStyle
                             range:(NSRange){0, attributedString.length}];

    if (lineHeight > fontLineHeight) {
      [attributedString addAttribute:NSBaselineOffsetAttributeName
                               value:@(lineHeight / 2 - fontLineHeight / 2)
                               range:(NSRange){0, attributedString.length}];
    }
  }

  // Text decoration
  if (_textDecorationLine == ABI10_0_0RCTTextDecorationLineTypeUnderline ||
      _textDecorationLine == ABI10_0_0RCTTextDecorationLineTypeUnderlineStrikethrough) {
    [self _addAttribute:NSUnderlineStyleAttributeName withValue:@(_textDecorationStyle)
     toAttributedString:attributedString];
  }
  if (_textDecorationLine == ABI10_0_0RCTTextDecorationLineTypeStrikethrough ||
      _textDecorationLine == ABI10_0_0RCTTextDecorationLineTypeUnderlineStrikethrough){
    [self _addAttribute:NSStrikethroughStyleAttributeName withValue:@(_textDecorationStyle)
     toAttributedString:attributedString];
  }
  if (_textDecorationColor) {
    [self _addAttribute:NSStrikethroughColorAttributeName withValue:_textDecorationColor
     toAttributedString:attributedString];
    [self _addAttribute:NSUnderlineColorAttributeName withValue:_textDecorationColor
     toAttributedString:attributedString];
  }

  // Text shadow
  if (!CGSizeEqualToSize(_textShadowOffset, CGSizeZero)) {
    NSShadow *shadow = [NSShadow new];
    shadow.shadowOffset = _textShadowOffset;
    shadow.shadowBlurRadius = _textShadowRadius;
    shadow.shadowColor = _textShadowColor;
    [self _addAttribute:NSShadowAttributeName withValue:shadow toAttributedString:attributedString];
  }
}

#pragma mark Autosizing

- (CGRect)calculateTextFrame:(NSTextStorage *)textStorage
{
  CGRect textFrame = UIEdgeInsetsInsetRect((CGRect){CGPointZero, self.frame.size},
                                           self.paddingAsInsets);
  

  if (_adjustsFontSizeToFit) {
    textFrame = [self updateStorage:textStorage toFitFrame:textFrame];
  }

  return textFrame;
}

- (CGRect)updateStorage:(NSTextStorage *)textStorage toFitFrame:(CGRect)frame
{

  BOOL fits = [self attemptScale:1.0f
                       inStorage:textStorage
                        forFrame:frame];
  CGSize requiredSize;
  if (!fits) {
    requiredSize = [self calculateOptimumScaleInFrame:frame
                                           forStorage:textStorage
                                             minScale:self.minimumFontScale
                                             maxScale:1.0
                                              prevMid:INT_MAX];
  } else {
    requiredSize = [self calculateSize:textStorage];
  }

  //Vertically center draw position for new text sizing.
  frame.origin.y = self.paddingAsInsets.top + ABI10_0_0RCTRoundPixelValue((CGRectGetHeight(frame) - requiredSize.height) / 2.0f);
  return frame;
}

- (CGSize)calculateOptimumScaleInFrame:(CGRect)frame
                            forStorage:(NSTextStorage *)textStorage
                              minScale:(CGFloat)minScale
                              maxScale:(CGFloat)maxScale
                               prevMid:(CGFloat)prevMid
{
  CGFloat midScale = (minScale + maxScale) / 2.0f;
  if (round((prevMid / ABI10_0_0RCTTextAutoSizeGranularity)) == round((midScale / ABI10_0_0RCTTextAutoSizeGranularity))) {
    //Bail because we can't meet error margin.
    return [self calculateSize:textStorage];
  } else {
    ABI10_0_0RCTSizeComparison comparison = [self attemptScale:midScale
                                            inStorage:textStorage
                                             forFrame:frame];
    if (comparison == ABI10_0_0RCTSizeWithinRange) {
      return [self calculateSize:textStorage];
    } else if (comparison == ABI10_0_0RCTSizeTooLarge) {
      return [self calculateOptimumScaleInFrame:frame
                                     forStorage:textStorage
                                       minScale:minScale
                                       maxScale:midScale - ABI10_0_0RCTTextAutoSizeGranularity
                                        prevMid:midScale];
    } else {
      return [self calculateOptimumScaleInFrame:frame
                                     forStorage:textStorage
                                       minScale:midScale + ABI10_0_0RCTTextAutoSizeGranularity
                                       maxScale:maxScale
                                        prevMid:midScale];
    }
  }
}

- (ABI10_0_0RCTSizeComparison)attemptScale:(CGFloat)scale
                        inStorage:(NSTextStorage *)textStorage
                         forFrame:(CGRect)frame
{
  NSLayoutManager *layoutManager = [textStorage.layoutManagers firstObject];
  NSTextContainer *textContainer = [layoutManager.textContainers firstObject];

  NSRange glyphRange = NSMakeRange(0, textStorage.length);
  [textStorage beginEditing];
  [textStorage enumerateAttribute:NSFontAttributeName
                           inRange:glyphRange
                           options:0
                        usingBlock:^(UIFont *font, NSRange range, BOOL *stop)
   {
     if (font) {
       UIFont *originalFont = [self.attributedString attribute:NSFontAttributeName
                                                       atIndex:range.location
                                                effectiveRange:&range];
       UIFont *newFont = [font fontWithSize:originalFont.pointSize * scale];
       [textStorage removeAttribute:NSFontAttributeName range:range];
       [textStorage addAttribute:NSFontAttributeName value:newFont range:range];
     }
   }];

  [textStorage endEditing];

  NSInteger linesRequired = [self numberOfLinesRequired:[textStorage.layoutManagers firstObject]];
  CGSize requiredSize = [self calculateSize:textStorage];

  BOOL fitSize = requiredSize.height <= CGRectGetHeight(frame) &&
  requiredSize.width <= CGRectGetWidth(frame);

  BOOL fitLines = linesRequired <= textContainer.maximumNumberOfLines ||
  textContainer.maximumNumberOfLines == 0;

  if (fitLines && fitSize) {
    if ((requiredSize.width + (CGRectGetWidth(frame) * ABI10_0_0RCTTextAutoSizeWidthErrorMargin)) > CGRectGetWidth(frame) &&
        (requiredSize.height + (CGRectGetHeight(frame) * ABI10_0_0RCTTextAutoSizeHeightErrorMargin)) > CGRectGetHeight(frame))
    {
      return ABI10_0_0RCTSizeWithinRange;
    } else {
      return ABI10_0_0RCTSizeTooSmall;
    }
  } else {
    return ABI10_0_0RCTSizeTooLarge;
  }
}

// Via Apple Text Layout Programming Guide
// https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/TextLayout/Tasks/CountLines.html
- (NSInteger)numberOfLinesRequired:(NSLayoutManager *)layoutManager
{
  NSInteger numberOfLines, index, numberOfGlyphs = [layoutManager numberOfGlyphs];
  NSRange lineRange;
  for (numberOfLines = 0, index = 0; index < numberOfGlyphs; numberOfLines++){
    (void) [layoutManager lineFragmentRectForGlyphAtIndex:index
                                           effectiveRange:&lineRange];
    index = NSMaxRange(lineRange);
  }

  return numberOfLines;
}

// Via Apple Text Layout Programming Guide
//https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/TextLayout/Tasks/StringHeight.html
- (CGSize)calculateSize:(NSTextStorage *)storage
{
  NSLayoutManager *layoutManager = [storage.layoutManagers firstObject];
  NSTextContainer *textContainer = [layoutManager.textContainers firstObject];

  [textContainer setLineBreakMode:NSLineBreakByWordWrapping];
  NSInteger maxLines = [textContainer maximumNumberOfLines];
  [textContainer setMaximumNumberOfLines:0];
  (void) [layoutManager glyphRangeForTextContainer:textContainer];
  CGSize requiredSize = [layoutManager usedRectForTextContainer:textContainer].size;
  [textContainer setMaximumNumberOfLines:maxLines];

  return requiredSize;
}

- (void)setBackgroundColor:(UIColor *)backgroundColor
{
  super.backgroundColor = backgroundColor;
  [self dirtyText];
}

#define ABI10_0_0RCT_TEXT_PROPERTY(setProp, ivar, type) \
- (void)set##setProp:(type)value;              \
{                                              \
  ivar = value;                                \
  [self dirtyText];                            \
}

ABI10_0_0RCT_TEXT_PROPERTY(AdjustsFontSizeToFit, _adjustsFontSizeToFit, BOOL)
ABI10_0_0RCT_TEXT_PROPERTY(Color, _color, UIColor *)
ABI10_0_0RCT_TEXT_PROPERTY(FontFamily, _fontFamily, NSString *)
ABI10_0_0RCT_TEXT_PROPERTY(FontSize, _fontSize, CGFloat)
ABI10_0_0RCT_TEXT_PROPERTY(FontWeight, _fontWeight, NSString *)
ABI10_0_0RCT_TEXT_PROPERTY(FontStyle, _fontStyle, NSString *)
ABI10_0_0RCT_TEXT_PROPERTY(FontVariant, _fontVariant, NSArray *)
ABI10_0_0RCT_TEXT_PROPERTY(IsHighlighted, _isHighlighted, BOOL)
ABI10_0_0RCT_TEXT_PROPERTY(LetterSpacing, _letterSpacing, CGFloat)
ABI10_0_0RCT_TEXT_PROPERTY(LineHeight, _lineHeight, CGFloat)
ABI10_0_0RCT_TEXT_PROPERTY(NumberOfLines, _numberOfLines, NSUInteger)
ABI10_0_0RCT_TEXT_PROPERTY(EllipsizeMode, _ellipsizeMode, NSLineBreakMode)
ABI10_0_0RCT_TEXT_PROPERTY(TextAlign, _textAlign, NSTextAlignment)
ABI10_0_0RCT_TEXT_PROPERTY(TextDecorationColor, _textDecorationColor, UIColor *);
ABI10_0_0RCT_TEXT_PROPERTY(TextDecorationLine, _textDecorationLine, ABI10_0_0RCTTextDecorationLineType);
ABI10_0_0RCT_TEXT_PROPERTY(TextDecorationStyle, _textDecorationStyle, NSUnderlineStyle);
ABI10_0_0RCT_TEXT_PROPERTY(WritingDirection, _writingDirection, NSWritingDirection)
ABI10_0_0RCT_TEXT_PROPERTY(Opacity, _opacity, CGFloat)
ABI10_0_0RCT_TEXT_PROPERTY(TextShadowOffset, _textShadowOffset, CGSize);
ABI10_0_0RCT_TEXT_PROPERTY(TextShadowRadius, _textShadowRadius, CGFloat);
ABI10_0_0RCT_TEXT_PROPERTY(TextShadowColor, _textShadowColor, UIColor *);

- (void)setAllowFontScaling:(BOOL)allowFontScaling
{
  _allowFontScaling = allowFontScaling;
  for (ABI10_0_0RCTShadowView *child in [self ReactABI10_0_0Subviews]) {
    if ([child isKindOfClass:[ABI10_0_0RCTShadowText class]]) {
      ((ABI10_0_0RCTShadowText *)child).allowFontScaling = allowFontScaling;
    }
  }
  [self dirtyText];
}

- (void)setFontSizeMultiplier:(CGFloat)fontSizeMultiplier
{
  _fontSizeMultiplier = fontSizeMultiplier;
  if (_fontSizeMultiplier == 0) {
    ABI10_0_0RCTLogError(@"fontSizeMultiplier value must be > zero.");
    _fontSizeMultiplier = 1.0;
  }
  for (ABI10_0_0RCTShadowView *child in [self ReactABI10_0_0Subviews]) {
    if ([child isKindOfClass:[ABI10_0_0RCTShadowText class]]) {
      ((ABI10_0_0RCTShadowText *)child).fontSizeMultiplier = fontSizeMultiplier;
    }
  }
  [self dirtyText];
}

- (void)setMinimumFontScale:(CGFloat)minimumFontScale
{
  if (minimumFontScale >= 0.01) {
    _minimumFontScale = minimumFontScale;
  }
  [self dirtyText];
}

@end