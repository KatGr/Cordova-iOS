//
//  PSPDFKit.m
//  PSPDFPlugin for Apache Cordova
//
//  Copyright © 2013-2017 PSPDFKit GmbH. All rights reserved.
//
//  THIS SOURCE CODE AND ANY ACCOMPANYING DOCUMENTATION ARE PROTECTED BY AUSTRIAN COPYRIGHT LAW
//  AND MAY NOT BE RESOLD OR REDISTRIBUTED. USAGE IS BOUND TO THE PSPDFKIT LICENSE AGREEMENT.
//  UNAUTHORIZED REPRODUCTION OR DISTRIBUTION IS SUBJECT TO CIVIL AND CRIMINAL PENALTIES.
//  This notice may not be removed from this file.
//

#import "PSPDFKitPlugin.h"
#import <WebKit/WebKit.h>
#import <PSPDFKit/PSPDFKit.h>
#import <PSPDFKitUI/PSPDFKitUI.h>

@interface PSPDFKitPlugin () <PSPDFViewControllerDelegate, PSPDFFlexibleToolbarContainerDelegate>

@property (nonatomic, strong) UINavigationController *navigationController;
@property (nonatomic, strong) PSPDFViewController *pdfController;
@property (nonatomic, strong) PSPDFDocument *pdfDocument;
@property (nonatomic, strong) NSDictionary *defaultOptions;

@end


@implementation PSPDFKitPlugin

#pragma mark Private methods

- (NSDictionary *)defaultOptions
{
    //this is an opportunity to provide
    //default options if we so choose
    if (!_defaultOptions) {
        _defaultOptions = @{};
    }
    return _defaultOptions;
}

- (void)setOptionsWithDictionary:(NSDictionary *)options animated:(BOOL)animated
{
    //merge with defaults
    NSMutableDictionary *newOptions = [self.defaultOptions mutableCopy];
    [newOptions addEntriesFromDictionary:options];
    self.defaultOptions = newOptions;

    [self resetBarButtonItemsIfNeededForOptions:newOptions];

    //set document and controller values
    [self setOptions:options forObject:_pdfController.document animated:animated];
    [self setOptions:options forObject:_pdfController animated:animated];
}

- (void)setOptions:(NSDictionary *)options forObject:(id)object animated:(BOOL)animated
{
    if (object) {

        //merge with defaults
        NSMutableDictionary *newOptions = [self.defaultOptions mutableCopy];
        [newOptions addEntriesFromDictionary:options];

        for (NSString *key in newOptions) {
            //generate setter prefix
            NSString *prefix = [NSString stringWithFormat:@"set%@%@", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];

            BOOL (^setterBlock)(NSString *, Class) = ^BOOL (NSString *suffix, Class klass) {
                NSString *setter = [[prefix stringByAppendingFormat:suffix, klass] stringByAppendingString:@":"];
                if ([self respondsToSelector:NSSelectorFromString(setter)]) {
                    [self setValue:newOptions[key] forKey:[key stringByAppendingFormat:suffix, klass]];
                    return YES;
                }
                return NO;
            };

            //try custom animated setter
            if (animated) {
                setterBlock(@"AnimatedFor%@WithJSON", [object class]);
            }
            else {
                //try custom setter
                if (!setterBlock(@"For%@WithJSON", [object class])) {
                    // Try the super class. For example, we try PSPDFDocument methods for Image Documents.
                    if (!setterBlock(@"For%@WithJSON", [object superclass])) {
                        //use KVC
                        NSString *setter = [prefix stringByAppendingString:@":"];
                        if ([object respondsToSelector:NSSelectorFromString(setter)]) {
                            [object setValue:newOptions[key] forKey:key];
                        }
                    }
                }
            }
        }
    }
}

- (id)optionAsJSON:(NSString *)key
{
    id value = nil;
    NSString *getterString = [key stringByAppendingFormat:@"AsJSON"];
    if ([self respondsToSelector:NSSelectorFromString(getterString)]) {
        value = [self valueForKey:getterString];
    }
    else if ([_pdfDocument respondsToSelector:NSSelectorFromString(key)]) {
        value = [_pdfDocument valueForKey:key];
    }
    else if ([_pdfController respondsToSelector:NSSelectorFromString(key)]) {
        value = [_pdfController valueForKey:key];
    }

    //determine type
    if ([value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSDictionary class]] ||
        [value isKindOfClass:[NSArray class]]) {
        return value;
    }
    else if ([value isKindOfClass:[NSSet class]]) {
        return [value allObjects];
    }
    else {
        return [value description];
    }
}

- (NSDictionary *)dictionaryWithError:(NSError *)error
{
    if (error) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"code"] = @(error.code);
        if (error.domain) dict[@"domain"] = error.domain;
        if ([error localizedDescription]) dict[@"description"] = [error localizedDescription];
        if ([error localizedFailureReason]) dict[@"reason"] = [error localizedFailureReason];
        return dict;
    }
    return nil;
}

- (NSDictionary *)standardColors
{
    //TODO: should we support all the standard css color names here?
    static NSDictionary *colors = nil;
    if (colors == nil) {
        colors = [[NSDictionary alloc] initWithObjectsAndKeys:
                  [UIColor blackColor], @"black", // 0.0 white
                  [UIColor darkGrayColor], @"darkgray", // 0.333 white
                  [UIColor lightGrayColor], @"lightgray", // 0.667 white
                  [UIColor whiteColor], @"white", // 1.0 white
                  [UIColor grayColor], @"gray", // 0.5 white
                  [UIColor redColor], @"red", // 1.0, 0.0, 0.0 RGB
                  [UIColor greenColor], @"green", // 0.0, 1.0, 0.0 RGB
                  [UIColor blueColor], @"blue", // 0.0, 0.0, 1.0 RGB
                  [UIColor cyanColor], @"cyan", // 0.0, 1.0, 1.0 RGB
                  [UIColor yellowColor], @"yellow", // 1.0, 1.0, 0.0 RGB
                  [UIColor magentaColor], @"magenta", // 1.0, 0.0, 1.0 RGB
                  [UIColor orangeColor], @"orange", // 1.0, 0.5, 0.0 RGB
                  [UIColor purpleColor], @"purple", // 0.5, 0.0, 0.5 RGB
                  [UIColor brownColor], @"brown", // 0.6, 0.4, 0.2 RGB
                  [UIColor clearColor], @"clear", // 0.0 white, 0.0 alpha
                  nil];
    }
    return colors;
}

- (UIColor *)colorWithString:(NSString *)string
{
    //convert to lowercase
    string = [string lowercaseString];

    //try standard colors first
    UIColor *color = [self standardColors][string];
    if (color) return color;

    //try rgb(a)
    if ([string hasPrefix:@"rgb"]) {
        string = [string substringToIndex:[string length] - 1];
        if ([string hasPrefix:@"rgb("]) {
            string = [string substringFromIndex:4];
        }
        else if ([string hasPrefix:@"rgba("]) {
            string = [string substringFromIndex:5];
        }
        CGFloat alpha = 1.0f;
        NSArray *components = [string componentsSeparatedByString:@","];
        if ([components count] > 3) {
            alpha = [[components[3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] floatValue];
        }
        if ([components count] > 2) {
            NSString *red = [components[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *green = [components[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *blue = [components[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            return [UIColor colorWithRed:[red floatValue] / 255.0f
                                   green:[green floatValue] / 255.0f
                                    blue:[blue floatValue] / 255.0f
                                   alpha:alpha];
        }
        return nil;
    }

    //try hex
    string = [string stringByReplacingOccurrencesOfString:@"#" withString:@""];
    switch ([string length])
    {
        case 0:
        {
            string = @"00000000";
            break;
        }
        case 3:
        {
            NSString *red = [string substringWithRange:NSMakeRange(0, 1)];
            NSString *green = [string substringWithRange:NSMakeRange(1, 1)];
            NSString *blue = [string substringWithRange:NSMakeRange(2, 1)];
            string = [NSString stringWithFormat:@"%1$@%1$@%2$@%2$@%3$@%3$@ff", red, green, blue];
            break;
        }
        case 6:
        {
            string = [string stringByAppendingString:@"ff"];
            break;
        }
        default:
        {
            return nil;
        }
    }
    uint32_t rgba;
    NSScanner *scanner = [NSScanner scannerWithString:string];
    [scanner scanHexInt:&rgba];
    CGFloat red = ((rgba & 0xFF000000) >> 24) / 255.0f;
    CGFloat green = ((rgba & 0x00FF0000) >> 16) / 255.0f;
    CGFloat blue = ((rgba & 0x0000FF00) >> 8) / 255.0f;
    return [UIColor colorWithRed:red green:green blue:blue alpha:1.0f];
}

- (void)getComponents:(CGFloat *)rgba ofColor:(UIColor *)color
{
    CGColorSpaceModel model = CGColorSpaceGetModel(CGColorGetColorSpace(color.CGColor));
    const CGFloat *components = CGColorGetComponents(color.CGColor);
    switch (model)
    {
        case kCGColorSpaceModelMonochrome:
        {
            rgba[0] = components[0];
            rgba[1] = components[0];
            rgba[2] = components[0];
            rgba[3] = components[1];
            break;
        }
        case kCGColorSpaceModelRGB:
        {
            rgba[0] = components[0];
            rgba[1] = components[1];
            rgba[2] = components[2];
            rgba[3] = components[3];
            break;
        }
        default:
        {
            rgba[0] = 0.0f;
            rgba[1] = 0.0f;
            rgba[2] = 0.0f;
            rgba[3] = 1.0f;
            break;
        }
    }
}

- (NSString *)colorAsString:(UIColor *)color
{
    //get components
    CGFloat rgba[4];
    [self getComponents:rgba ofColor:color];
    return [NSString stringWithFormat:@"rgba(%i,%i,%i,%g)",
            (int)round(rgba[0]*255), (int)round(rgba[1]*255),
            (int)round(rgba[2]*255), rgba[3]];
}

- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script {
    __block NSString *result;
    if ([self.webView isKindOfClass:UIWebView.class]) {
        result = [(UIWebView *)self.webView stringByEvaluatingJavaScriptFromString:script];
    } else {
        runOnMainQueueWithoutDeadlocking(^{
            [((WKWebView *)self.webView) evaluateJavaScript:script completionHandler:^(id resultID, NSError *error) {
                result = [resultID description];
            }];
        });
    }
    return result;
}

// http://stackoverflow.com/questions/5225130/grand-central-dispatch-gcd-vs-performselector-need-a-better-explanation/5226271#5226271
void runOnMainQueueWithoutDeadlocking(void (^block)(void))
{
    if ([NSThread isMainThread])
    {
        block();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

- (BOOL)sendEventWithJSON:(id)JSON
{
    if ([JSON isKindOfClass:[NSDictionary class]]) {
        JSON = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:JSON options:0 error:NULL] encoding:NSUTF8StringEncoding];
    }
    NSString *script = [NSString stringWithFormat:@"PSPDFKitPlugin.dispatchEvent(%@)", JSON];
    NSString *result = [self stringByEvaluatingJavaScriptFromString:script];
    return [result length]? [result boolValue]: YES;
}

- (BOOL)isNumeric:(id)value
{
    if ([value isKindOfClass:[NSNumber class]]) return YES;
    static NSNumberFormatter *formatter = nil;
    if (formatter == nil)
    {
        formatter = [[NSNumberFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    }
    return [formatter numberFromString:value] != nil;
}

- (UIBarButtonItem *)standardBarButtonWithName:(NSString *)name
{
    NSString *selectorString = [name stringByAppendingString:@"ButtonItem"];
    if ([_pdfController respondsToSelector:NSSelectorFromString(selectorString)]) {
        return [_pdfController valueForKey:selectorString];
    }
    return nil;
}

- (UIBarButtonItem *)barButtonItemWithJSON:(id)JSON
{
    if ([JSON isKindOfClass:[NSString class]]) {
        return [self standardBarButtonWithName:JSON];
    }
    else if ([JSON isKindOfClass:[NSDictionary class]]) {

        UIImage *image = nil;
        NSString *imagePath = JSON[@"image"];
        if (imagePath) {
            imagePath = [@"www" stringByAppendingPathComponent:imagePath];
            image = [UIImage imageNamed:imagePath];
        }

        UIImage *landscapeImage = image;
        imagePath = JSON[@"landscapeImage"];
        if (imagePath) {
            imagePath = [@"www" stringByAppendingPathComponent:imagePath];
            landscapeImage = [UIImage imageNamed:imagePath] ?: landscapeImage;
        }

        UIBarButtonItemStyle style = [self enumValueForKey:JSON[@"style"]
                                                    ofType:@"UIBarButtonItemStyle"
                                               withDefault:UIBarButtonItemStylePlain];

        UIBarButtonItem *item = nil;
        if (image) {
            item = [[UIBarButtonItem alloc] initWithImage:image landscapeImagePhone:landscapeImage style:style target:self action:@selector(customBarButtonItemAction:)];
        }
        else {
            item = [[UIBarButtonItem alloc] initWithTitle:JSON[@"title"] style:style target:self action:@selector(customBarButtonItemAction:)];
        }

        item.tintColor = JSON[@"tintColor"]? [self colorWithString:JSON[@"tintColor"]]: item.tintColor;
        return item;
    }
    return nil;
}

- (NSArray *)barButtonItemsWithArray:(NSArray *)array
{
    NSMutableArray *items = [NSMutableArray array];
    for (id JSON in array) {
        UIBarButtonItem *item = [self barButtonItemWithJSON:JSON];
        if (item) {
            [items addObject:item];
        }
        else {
            NSLog(@"Unrecognised toolbar button name or format: %@", JSON);
        }
    }
    return items;
}

- (void)customBarButtonItemAction:(UIBarButtonItem *)sender
{
    NSInteger index = [_pdfController.navigationItem.leftBarButtonItems indexOfObject:sender];
    if (index == NSNotFound) {
        index = [_pdfController.navigationItem.rightBarButtonItems indexOfObject:sender];
        if (index != NSNotFound) {
            NSString *script = [NSString stringWithFormat:@"PSPDFKitPlugin.dispatchRightBarButtonAction(%ld)", (long)index];
            [self stringByEvaluatingJavaScriptFromString:script];
        }
    }
    else {
        NSString *script = [NSString stringWithFormat:@"PSPDFKitPlugin.dispatchLeftBarButtonAction(%ld)", (long)index];
        [self stringByEvaluatingJavaScriptFromString:script];
    }
}

- (NSURL *)pdfFileURLWithPath:(NSString *)path
{
    if (path) {
        path = [path stringByExpandingTildeInPath];
        path = [path stringByReplacingOccurrencesOfString:@"file:" withString:@""];
        if (![path isAbsolutePath]) {
            path = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"www"] stringByAppendingPathComponent:path];
        }
        return [NSURL fileURLWithPath:path];
    }
    return nil;
}

- (BOOL)isImagePath:(NSString *)path {
    NSString *pathExtension = path.pathExtension.lowercaseString;
    return [pathExtension isEqualToString:@"png"] || [pathExtension isEqualToString:@"jpeg"] || [pathExtension isEqualToString:@"jpg"];
}

- (NSInteger)enumValueForKey:(NSString *)key ofType:(NSString *)type withDefault:(int)defaultValue
{
    NSNumber *number = key? [self enumValuesOfType:type][key]: nil;
    if (number) return [number integerValue];
    if ([self isNumeric:key]) return [key integerValue];
    return defaultValue;
}

- (NSString *)enumKeyForValue:(int)value ofType:(NSString *)type
{
    NSDictionary *dict = [self enumValuesOfType:type];
    NSInteger index = [[dict allValues] indexOfObject:@(value)];
    if (index != NSNotFound) {
        return [[dict allKeys] objectAtIndex:index];
    }
    return nil;
}

- (NSInteger)optionsValueForKeys:(NSArray *)keys ofType:(NSString *)type withDefault:(NSInteger)defaultValue
{
    if (!keys)
    {
        return 0;
    }
    if ([keys isKindOfClass:NSNumber.class]) {
        if (((NSNumber *)keys).integerValue == 0) {
            return 0;
        }
    }
    if (![keys isKindOfClass:[NSArray class]])
    {
        keys = @[keys];
    }
    if ([keys count] == 0)
    {
        return defaultValue;
    }
    NSInteger value = 0;
    for (id key in keys)
    {
        NSNumber *number = [self enumValuesOfType:type][key];
        if (number)
        {
            value += [number integerValue];
        }
        else
        {
            if ([key isKindOfClass:NSString.class])
            {
                // Try to find with uppercase first letter
                NSString *keyStr = [NSString stringWithFormat:@"%@%@", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];
                number = [self enumValuesOfType:type][keyStr];
                if (number) {
                    value += [number integerValue];
                }
            }
            else if ([self isNumeric:key])
            {
                value += [key integerValue];
            }
        }
    }
    return value;
}

- (NSArray *)optionKeysForValue:(NSUInteger)value ofType:(NSString *)type
{
    NSDictionary *dict = [self enumValuesOfType:type];
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *key in dict)
    {
        NSNumber *number = dict[key];
        if (number) {
            if ([number unsignedIntegerValue] == NSUIntegerMax)
            {
                if (value == NSUIntegerMax)
                {
                    return @[key];
                }
            } else {
                if (value & [number unsignedIntegerValue])
                {
                    [keys addObject:key];
                }
            }
        }
    }
    return keys;
}

- (void)resetBarButtonItemsIfNeededForOptions:(NSDictionary *)options
{
    // Reset left- and rightBarButtonItems to not cause duplicated button issues
    if ([options.allKeys containsObject:@"leftBarButtonItems"] && [options.allKeys containsObject:@"rightBarButtonItems"]) {
        NSDictionary *resetBarButtonsOptions = @{@"leftBarButtonItems": @[], @"rightBarButtonItems": @[]};
        [self setOptions:resetBarButtonsOptions forObject:_pdfController animated:NO];
    }
}

#pragma mark Enums and options

- (NSDictionary *)enumValuesOfType:(NSString *)type
{
    static NSDictionary *enumsByType = nil;
    if (!enumsByType) {
        enumsByType = @{

                        @"UIBarButtonItemStyle":

                            @{@"plain": @(UIBarButtonItemStylePlain),
                              @"done": @(UIBarButtonItemStyleDone)},

                        @"PSPDFAnnotationSaveMode":

                            @{@"disabled": @(PSPDFAnnotationSaveModeDisabled),
                              @"externalFile": @(PSPDFAnnotationSaveModeExternalFile),
                              @"embedded": @(PSPDFAnnotationSaveModeEmbedded),
                              @"embeddedWithExternalFileAsFallback": @(PSPDFAnnotationSaveModeEmbeddedWithExternalFileAsFallback)},

                        @"PSPDFTextCheckingType":

                            @{@"link": @(PSPDFTextCheckingTypeLink),
                              @"phoneNumber": @(PSPDFTextCheckingTypePhoneNumber),
                              @"all": @(PSPDFTextCheckingTypeAll)},

                        @"PSPDFTextSelectionMenuAction":

                            @{@"search": @(PSPDFTextSelectionMenuActionSearch),
                              @"define": @(PSPDFTextSelectionMenuActionDefine),
                              @"wikipedia": @(PSPDFTextSelectionMenuActionWikipedia),
                              @"speak": @(PSPDFTextSelectionMenuActionSpeak),
                              @"all": @(PSPDFTextSelectionMenuActionAll)},

                        @"PSPDFPageTransition":

                            @{@"scrollPerSpread": @(PSPDFPageTransitionScrollPerSpread),
                              @"scrollContinuous": @(PSPDFPageTransitionScrollContinuous),
                              @"curl": @(PSPDFPageTransitionCurl)},

                        @"PSPDFViewMode":

                            @{@"document": @(PSPDFViewModeDocument),
                              @"thumbnails": @(PSPDFViewModeThumbnails)},

                        @"PSPDFPageMode":

                            @{@"single": @(PSPDFPageModeSingle),
                              @"double": @(PSPDFPageModeDouble),
                              @"automatic": @(PSPDFPageModeAutomatic)},

                        @"PSPDFScrollDirection":

                            @{@"horizontal": @(PSPDFScrollDirectionHorizontal),
                              @"vertical": @(PSPDFScrollDirectionVertical)},

                        @"PSPDFLinkAction":

                            @{@"none": @(PSPDFLinkActionNone),
                              @"alertView": @(PSPDFLinkActionAlertView),
                              @"openSafari": @(PSPDFLinkActionOpenSafari),
                              @"inlineBrowser": @(PSPDFLinkActionInlineBrowser)},

                        @"PSPDFUserInterfaceViewMode":

                            @{@"always": @(PSPDFUserInterfaceViewModeAlways),
                              @"automatic": @(PSPDFUserInterfaceViewModeAutomatic),
                              @"automaticNoFirstLastPage": @(PSPDFUserInterfaceViewModeAutomaticNoFirstLastPage),
                              @"never": @(PSPDFUserInterfaceViewModeNever)},

                        @"PSPDFUserInterfaceViewAnimation":

                            @{@"none": @(PSPDFUserInterfaceViewAnimationNone),
                              @"fade": @(PSPDFUserInterfaceViewAnimationFade),
                              @"slide": @(PSPDFUserInterfaceViewAnimationSlide)},

                        @"PSPDFThumbnailBarMode":

                            @{@"none": @(PSPDFThumbnailBarModeNone),
                              @"scrobbleBar": @(PSPDFThumbnailBarModeScrubberBar),
                              @"scrollable": @(PSPDFThumbnailBarModeScrollable)},

                        @"PSPDFAnnotationType":

                            @{@"None": @(PSPDFAnnotationTypeNone),
                              @"Undefined": @(PSPDFAnnotationTypeUndefined),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeLink): @(PSPDFAnnotationTypeLink),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeHighlight): @(PSPDFAnnotationTypeHighlight),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeStrikeOut): @(PSPDFAnnotationTypeStrikeOut),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeUnderline): @(PSPDFAnnotationTypeUnderline),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeSquiggly): @(PSPDFAnnotationTypeSquiggly),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeFreeText): @(PSPDFAnnotationTypeFreeText),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeInk): @(PSPDFAnnotationTypeInk),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeSquare): @(PSPDFAnnotationTypeSquare),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeCircle): @(PSPDFAnnotationTypeCircle),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeLine): @(PSPDFAnnotationTypeLine),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeNote): @(PSPDFAnnotationTypeNote),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeStamp): @(PSPDFAnnotationTypeStamp),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeCaret): @(PSPDFAnnotationTypeCaret),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeRichMedia): @(PSPDFAnnotationTypeRichMedia),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeScreen): @(PSPDFAnnotationTypeScreen),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeWidget): @(PSPDFAnnotationTypeWidget),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeSound): @(PSPDFAnnotationTypeSound),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeFile): @(PSPDFAnnotationTypeFile),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypePolygon): @(PSPDFAnnotationTypePolygon),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypePolyLine): @(PSPDFAnnotationTypePolyLine),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypePopup): @(PSPDFAnnotationTypePopup),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeWatermark): @(PSPDFAnnotationTypeWatermark),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeTrapNet): @(PSPDFAnnotationTypeTrapNet),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeThreeDimensional): @(PSPDFAnnotationTypeThreeDimensional),
                              PSPDFStringFromAnnotationType(PSPDFAnnotationTypeRedaction): @(PSPDFAnnotationTypeRedaction),
                              @"All": @(PSPDFAnnotationTypeAll)},

                        @"PSPDFAppearanceMode":

                            @{@"default": @(PSPDFAppearanceModeDefault),
                              @"sepia": @(PSPDFAppearanceModeSepia),
                              @"night": @(PSPDFAppearanceModeNight)},

//                        @"PSPDFDocumentSharingOptions":
//
//                            @{@"None": @(PSPDFDocumentSharingOptionNone),
//                              @"CurrentPageOnly": @(PSPDFDocumentSharingOptionCurrentPageOnly),
//                              @"PageRange": @(PSPDFDocumentSharingOptionPageRange),
//                              @"AllPages": @(PSPDFDocumentSharingOptionAllPages),
//                              @"AnnotatedPages": @(PSPDFDocumentSharingOptionAnnotatedPages),
//                              @"EmbedAnnotations": @(PSPDFDocumentSharingOptionEmbedAnnotations),
//                              @"FlattenAnnotations": @(PSPDFDocumentSharingOptionFlattenAnnotations),
//                              @"AnnotationsSummary": @(PSPDFDocumentSharingOptionAnnotationsSummary),
//                              @"RemoveAnnotations": @(PSPDFDocumentSharingOptionRemoveAnnotations),
//                              @"FlattenAnnotationsForPrint": @(PSPDFDocumentSharingOptionFlattenAnnotationsForPrint),
//                              @"OriginalFile": @(PSPDFDocumentSharingOptionOriginalFile),
//                              @"Image": @(PSPDFDocumentSharingOptionImage)},

                        };

        //Note: this method crashes the second time a
        //PDF is opened if the dictionary is not copied.
        //Somehow the enumsByType dictionary is released
        //and becomes a dangling pointer, which really
        //shouldn't be possible since we are using ARC
        enumsByType = [enumsByType copy];
    }
    return enumsByType[type];
}

#pragma mark License Key

- (void)setLicenseKey:(CDVInvokedUrlCommand *)command {
    NSString *key = [command argumentAtIndex:0];
    if (key.length > 0) {
        [PSPDFKit setLicenseKey:key];
    }
}

#pragma mark PSPDFDocument setters and getters

- (void)setFileURLForPSPDFDocumentWithJSON:(NSString *)path
{
    // Brute-Force-Set.
    [_pdfDocument setValue:[self pdfFileURLWithPath:path] forKey:@"fileURL"];
}

- (NSString *)fileURLAsJSON
{
    return _pdfDocument.fileURL.path;
}

- (void)setEditableAnnotationTypesForPSPDFViewControllerWithJSON:(NSArray *)types
{
    if (![types isKindOfClass:[NSArray class]])
    {
        types = @[types];
    }

    NSMutableSet *qualified = [[NSMutableSet alloc] init];
    for (NSString *type in types)
    {
        NSString *prefix = @"PSPDFAnnotationType";
        if ([type hasPrefix:prefix]) {
            [qualified addObject:[type substringFromIndex:prefix.length]];
        }
        else if ([type length]) {
            [qualified addObject:[NSString stringWithFormat:@"%@%@", [[type substringToIndex:1] uppercaseString], [type substringFromIndex:1]]];
        }
    }

    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.editableAnnotationTypes = qualified;
    }];
}

- (NSArray *)editableAnnotationTypesAsJSON
{
    return _pdfController.configuration.editableAnnotationTypes.allObjects;
}

- (void)setAnnotationSaveModeForPSPDFDocumentWithJSON:(NSString *)option
{
    _pdfDocument.annotationSaveMode = [self enumValueForKey:option ofType:@"PSPDFAnnotationSaveMode" withDefault:PSPDFAnnotationSaveModeEmbeddedWithExternalFileAsFallback];
}

- (NSString *)annotationSaveModeAsJSON
{
    return [self enumKeyForValue:_pdfDocument.annotationSaveMode ofType:@"PSPDFAnnotationSaveMode"];
}

- (void)setPageBackgroundColorForPSPDFDocumentWithJSON:(NSString *)color
{
    NSMutableDictionary *renderOptions = [[_pdfDocument renderOptionsForType:PSPDFRenderTypeAll context:nil] mutableCopy];
    renderOptions[PSPDFRenderOptionBackgroundFillColorKey] = [self colorWithString:color];
    [_pdfDocument setRenderOptions:renderOptions type:PSPDFRenderTypeAll];
}

- (NSString *)pageBackgroundColorAsJSON
{
    NSDictionary *renderOptions = [_pdfDocument renderOptionsForType:PSPDFRenderTypeAll context:nil];
    return [self colorAsString:renderOptions[PSPDFRenderOptionBackgroundFillColorKey]];
}

- (void)setBackgroundColorForPSPDFDocumentWithJSON:(NSString *)color
{
    //not supported, use pageBackgroundColor instead
}

- (NSArray *)renderAnnotationTypesAsJSON
{
    NSArray *types = [self optionKeysForValue:_pdfDocument.renderAnnotationTypes ofType:@"PSPDFAnnotationType"];
    return types;
}

- (void)setRenderAnnotationTypesForPSPDFDocumentWithJSON:(NSArray *)options
{
    PSPDFAnnotationType types = (PSPDFAnnotationType) [self optionsValueForKeys:options ofType:@"PSPDFAnnotationType" withDefault:PSPDFAnnotationTypeAll];
    _pdfDocument.renderAnnotationTypes = types;
}

#pragma mark PSPDFViewController setters and getters

- (void)setPageTransitionForPSPDFViewControllerWithJSON:(NSString *)transition
{
    PSPDFPageTransition pageTransition = (PSPDFPageTransition) [self enumValueForKey:transition ofType:@"PSPDFPageTransition" withDefault:PSPDFPageTransitionScrollPerSpread];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.pageTransition = pageTransition;
    }];
}

- (NSString *)pageTransitionAsJSON
{
    return [self enumKeyForValue:_pdfController.configuration.pageTransition ofType:@"PSPDFPageTransition"];
}

- (void)setViewModeAnimatedForPSPDFViewControllerWithJSON:(NSString *)mode
{
    [_pdfController setViewMode:[self enumValueForKey:mode ofType:@"PSPDFViewMode" withDefault:PSPDFViewModeDocument] animated:YES];
}

- (void)setViewModeForPSPDFViewControllerWithJSON:(NSString *)mode
{
    _pdfController.viewMode = [self enumValueForKey:mode ofType:@"PSPDFViewMode" withDefault:PSPDFViewModeDocument];
}

- (NSString *)viewModeAsJSON
{
    return [self enumKeyForValue:_pdfController.viewMode ofType:@"PSPDFViewMode"];
}

- (void)setThumbnailBarModeForPSPDFViewControllerWithJSON:(NSString *)mode
{
    PSPDFThumbnailBarMode thumbnailBarMode = (PSPDFThumbnailBarMode) [self enumValueForKey:mode ofType:@"PSPDFThumbnailBarMode" withDefault:PSPDFThumbnailBarModeScrubberBar];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.thumbnailBarMode = thumbnailBarMode;
    }];
}

- (NSString *)thumbnailBarMode
{
    return [self enumKeyForValue:_pdfController.configuration.thumbnailBarMode ofType:@"PSPDFThumbnailBarMode"];
}

- (void)setPageModeForPSPDFViewControllerWithJSON:(NSString *)mode
{
    PSPDFPageMode pageMode = (PSPDFPageMode) [self enumValueForKey:mode ofType:@"PSPDFPageMode" withDefault:PSPDFPageModeAutomatic];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.pageMode = pageMode;
    }];
}

- (NSString *)pageModeAsJSON
{
    return [self enumKeyForValue:_pdfController.configuration.pageMode ofType:@"PSPDFPageMode"];
}

- (void)setScrollDirectionForPSPDFViewControllerWithJSON:(NSString *)mode
{
    PSPDFScrollDirection scrollDirection = (PSPDFScrollDirection) [self enumValueForKey:mode ofType:@"PSPDFScrollDirection" withDefault:PSPDFScrollDirectionHorizontal];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.scrollDirection = scrollDirection;
    }];
}

- (NSString *)scrollDirectionAsJSON
{
    return [self enumKeyForValue:_pdfController.configuration.scrollDirection ofType:@"PSPDFScrollDirection"];
}

- (void)setLinkActionForPSPDFViewControllerWithJSON:(NSString *)mode
{
    PSPDFLinkAction linkAction = (PSPDFLinkAction) [self enumValueForKey:mode ofType:@"PSPDFLinkAction" withDefault:PSPDFLinkActionInlineBrowser];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.linkAction = linkAction;
    }];
}

- (NSString *)linkActionAsJSON
{
    return [self enumKeyForValue:_pdfController.configuration.linkAction ofType:@"PSPDFLinkAction"];
}

- (void)setUserInterfaceViewModeForPSPDFViewControllerWithJSON:(NSString *)mode
{
    PSPDFUserInterfaceViewMode userInterfaceViewMode = (PSPDFUserInterfaceViewMode) [self enumValueForKey:mode ofType:@"PSPDFUserInterfaceViewMode" withDefault:PSPDFUserInterfaceViewModeAutomatic];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.userInterfaceViewMode = userInterfaceViewMode;
    }];
}

- (NSString *)userInterfaceViewModeAsJSON
{
    return [self enumKeyForValue:_pdfController.configuration.userInterfaceViewMode ofType:@"PSPDFUserInterfaceViewMode"];
}

- (void)setUserInterfaceViewAnimationForPSPDFViewControllerWithJSON:(NSString *)mode
{
    PSPDFUserInterfaceViewAnimation userInterfaceViewAnimation = (PSPDFUserInterfaceViewAnimation) [self enumValueForKey:mode ofType:@"UserInterfaceViewAnimation" withDefault:PSPDFUserInterfaceViewAnimationFade];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.userInterfaceViewAnimation = userInterfaceViewAnimation;
    }];
}

- (NSString *)userInterfaceViewAnimationAsJSON
{
    return [self enumKeyForValue:_pdfController.configuration.userInterfaceViewAnimation ofType:@"PSPDFUserInterfaceViewAnimation"];
}

- (void)setUserInterfaceVisibleAnimatedForPSPDFViewControllerWithJSON:(NSNumber *)visible
{
    [_pdfController setUserInterfaceVisible:[visible boolValue] animated:YES];
}

- (void)setPageAnimatedForPSPDFViewControllerWithJSON:(NSNumber *)page
{
    [_pdfController setPageIndex:[page integerValue] animated:YES];
}

- (void)setLeftBarButtonItemsForPSPDFViewControllerWithJSON:(NSArray *)items
{
    _pdfController.navigationItem.closeBarButtonItem = nil;
    _pdfController.navigationItem.leftBarButtonItems = [self barButtonItemsWithArray:items] ?: _pdfController.navigationItem.leftBarButtonItems;
}

- (void)setRightBarButtonItemsForPSPDFViewControllerWithJSON:(NSArray *)items
{
    _pdfController.navigationItem.rightBarButtonItems = [self barButtonItemsWithArray:items] ?: _pdfController.navigationItem.rightBarButtonItems;
}

- (void)setTintColorForPSPDFViewControllerWithJSON:(NSString *)color
{
    _pdfController.view.tintColor = [self colorWithString:color];
}

- (NSString *)tintColorAsJSON
{
    return [self colorAsString:_pdfController.view.tintColor];
}

- (void)setBackgroundColorForPSPDFViewControllerWithJSON:(NSString *)color
{
    UIColor *backgroundColor = [self colorWithString:color];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.backgroundColor = backgroundColor;
    }];
}

- (NSString *)backgroundColorAsJSON
{
    return [self colorAsString:_pdfController.configuration.backgroundColor];
}

- (void)setAllowedMenuActionsForPSPDFViewControllerWithJSON:(NSArray *)options
{
    PSPDFTextSelectionMenuAction menuActions = (PSPDFTextSelectionMenuAction) [self optionsValueForKeys:options ofType:@"PSPDFTextSelectionMenuAction" withDefault:PSPDFTextSelectionMenuActionAll];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.allowedMenuActions = menuActions;
    }];
}

- (NSArray *)allowedMenuActionsAsJSON
{
    return [self optionKeysForValue:_pdfController.configuration.allowedMenuActions ofType:@"PSPDFTextSelectionMenuAction"];
}

//- (void)setPrintSharingOptionsForPSPDFViewControllerWithJSON:(NSArray *)options
//{
//    if (![options isKindOfClass:[NSArray class]])
//    {
//        options = @[options];
//    }
//
//    NSUInteger sharingOptions = 0;
//    for (NSString *option in options)
//    {
//        if ([option length]) {
//            NSInteger newOption = [self enumValueForKey:[NSString stringWithFormat:@"%@%@", [[option substringToIndex:1] uppercaseString], [option substringFromIndex:1]] ofType:@"PSPDFDocumentSharingOptions" withDefault:PSPDFDocumentSharingOptionNone];
//            sharingOptions = sharingOptions | newOption;
//        }
//    }
//
//    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
//        builder.printSharingOptions = sharingOptions;
//    }];
//}

//- (NSNumber *)printSharingOptionsAsJSON
//{
//    return @(_pdfController.configuration.printSharingOptions);
//}

- (void)setShouldAskForAnnotationUsernameForPSPDFViewControllerWithJSON:(NSNumber *)shouldAskForAnnotationUsername
{
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.shouldAskForAnnotationUsername = shouldAskForAnnotationUsername.boolValue;
    }];
}

- (NSNumber *)shouldAskForAnnotationUsernameAsJSON
{
    return @(_pdfController.configuration.shouldAskForAnnotationUsername);
}

- (void)setPageGrabberEnabledForPSPDFViewControllerWithJSON:(NSNumber *)pageGrabberEnabled
{
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.pageGrabberEnabled = pageGrabberEnabled.boolValue;
    }];
}

- (NSNumber *)pageGrabberEnabledAsJSON
{
    return @(_pdfController.configuration.pageGrabberEnabled);
}

- (void)setPageLabelEnabledForPSPDFViewControllerWithJSON:(NSNumber *)pageLabelEnabled
{
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.pageLabelEnabled = pageLabelEnabled.boolValue;
    }];
}

- (NSNumber *)pageLabelEnabledAsJSON
{
    return @(_pdfController.configuration.pageLabelEnabled);
}

- (void)setDocumentLabelEnabledForPSPDFViewControllerWithJSON:(NSNumber *)documentLabelEnabled
{
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.documentLabelEnabled = documentLabelEnabled.boolValue;
    }];
}

- (NSNumber *)documentLabelEnabledAsJSON
{
    return @(_pdfController.configuration.documentLabelEnabled);
}

#pragma mark PDFProcessing methods

- (void)convertPDFFromHTMLString:(CDVInvokedUrlCommand *)command
{
    NSString *decodeHTMLString = [[[command argumentAtIndex:0] stringByReplacingOccurrencesOfString:@"+" withString:@""]stringByRemovingPercentEncoding];
    NSString *fileName = [command argumentAtIndex:1 withDefault:@"Sample"];
    NSDictionary *options = [command argumentAtIndex:2 withDefault:nil];
    NSString *outputFilePath = [NSTemporaryDirectory()
                                stringByAppendingPathComponent:[fileName stringByAppendingPathExtension:@"pdf"]];

    void (^completionBlock)(NSError *error) = ^(NSError *error) {
        CDVPluginResult *pluginResult;

        if (error)
        {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsDictionary:@{@"localizedDescription": error.localizedDescription, @"domin": error.domain}];
        }
        else
        {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                         messageAsDictionary:@{@"filePath":outputFilePath}];
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    };

    [self generatePDFFromHTMLString:decodeHTMLString outputFile:outputFilePath options:options completionBlock:completionBlock];
}

- (void)generatePDFFromHTMLString:(NSString *)html outputFile:(NSString *)filePath options:(NSDictionary *)options completionBlock:(void (^)(NSError *error))completionBlock
{
    PSPDFProcessor *processor = [[PSPDFProcessor alloc] initWithOptions:nil];
    [processor convertHTMLString:html outputFileURL:[NSURL fileURLWithPath:filePath] completionBlock:completionBlock];
}

#pragma mark Document methods

- (void)present:(CDVInvokedUrlCommand *)command {
    NSString *path = [command argumentAtIndex:0];
    NSDictionary *options = [command argumentAtIndex:1] ?: [command argumentAtIndex:2];

    // merge options with defaults
    NSMutableDictionary *newOptions = [self.defaultOptions mutableCopy];
    [newOptions addEntriesFromDictionary:options];

    if (path) {
        //configure document
        NSURL *url = [self pdfFileURLWithPath:path];
        if ([self isImagePath:path]) {
            _pdfDocument = [[PSPDFImageDocument alloc] initWithImageURL:url];
        }
        else {
            _pdfDocument = [[PSPDFDocument alloc] initWithURL:url];
        }
        [self setOptions:newOptions forObject:_pdfDocument animated:NO];
    }

    // configure controller
    if (!_pdfController) {
        _pdfController = [[PSPDFViewController alloc] init];
        _pdfController.delegate = self;
        _pdfController.annotationToolbarController.delegate = self;
        _navigationController = [[UINavigationController alloc] initWithRootViewController:_pdfController];
    }

    [self resetBarButtonItemsIfNeededForOptions:newOptions];

    [self setOptions:newOptions forObject:_pdfController animated:NO];
    _pdfController.document = _pdfDocument;

    //present controller
    if (!_navigationController.presentingViewController) {
        [self.viewController presentViewController:_navigationController animated:YES completion:^{

            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                        callbackId:command.callbackId];
        }];
    }
    else {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR]
                                    callbackId:command.callbackId];
    }
}

- (void)dismiss:(CDVInvokedUrlCommand *)command
{
    [_navigationController.presentingViewController dismissViewControllerAnimated:YES completion:^{

        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                    callbackId:command.callbackId];
    }];
}

- (void)reload:(CDVInvokedUrlCommand *)command
{
    [_pdfController reloadData];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

- (void)search:(CDVInvokedUrlCommand *)command
{
    CDVPluginResult *pluginResult = nil;
    NSString *query = [command argumentAtIndex:0];
    BOOL animated = [[command argumentAtIndex:1 withDefault:@NO] boolValue];
    BOOL headless = [[command argumentAtIndex:2 withDefault:@NO] boolValue];

    if (query) {
        [_pdfController searchForString:query options:@{PSPDFViewControllerSearchHeadlessKey: @(headless)} sender:nil animated:animated];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"'query' argument was null"];
    }

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)saveAnnotations:(CDVInvokedUrlCommand *)command
{
    // Completion handler is called on the main queue
    [_pdfController.document saveWithOptions:nil completionHandler:^(NSError * _Nullable error, NSArray<__kindof PSPDFAnnotation *> * _Nonnull savedAnnotations) {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[self dictionaryWithError:error]] callbackId:command.callbackId];
    }];
}

- (void)getHasDirtyAnnotations:(CDVInvokedUrlCommand *)command
{
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:_pdfDocument.hasDirtyAnnotations] callbackId:command.callbackId];
}

#pragma mark Configuration

- (void)setOptions:(CDVInvokedUrlCommand *)command
{
    NSDictionary *options = [command argumentAtIndex:0];
    BOOL animated = [[command argumentAtIndex:1 withDefault:@NO] boolValue];
    [self setOptionsWithDictionary:options animated:animated];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

- (void)setOption:(CDVInvokedUrlCommand *)command
{
    CDVPluginResult *pluginResult = nil;
    NSString *key = [command argumentAtIndex:0];
    id value = [command argumentAtIndex:1];
    BOOL animated = [[command argumentAtIndex:2 withDefault:@NO] boolValue];

    if (key && value) {
        [self setOptionsWithDictionary:@{key: value} animated:animated];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"'key' and/or 'value' argument was null"];
    }

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)getOptions:(CDVInvokedUrlCommand *)command
{
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSArray *names = [command argumentAtIndex:0];
    for (NSString *name in names) {
        id value = [self optionAsJSON:name];
        if (value) values[name] = value;
    }

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:values] callbackId:command.callbackId];
}

- (void)getOption:(CDVInvokedUrlCommand *)command
{
    NSString *key = [command argumentAtIndex:0];
    if (key)
    {
        id value = [self optionAsJSON:key];

        //determine type
        if ([value isKindOfClass:[NSNumber class]]) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:[value doubleValue]] callbackId:command.callbackId];
        }
        else if ([value isKindOfClass:[NSDictionary class]]) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:value] callbackId:command.callbackId];
        }
        else if ([value isKindOfClass:[NSArray class]]) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:value] callbackId:command.callbackId];
        }
        else if (value) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:value] callbackId:command.callbackId];
        }
        else {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
        }
    }
}

#pragma mark Appearance

- (void)setAppearanceMode:(CDVInvokedUrlCommand *)command {
    NSString *appearanceMode = [command argumentAtIndex:0];
    NSInteger value = [self enumValueForKey:appearanceMode ofType:@"PSPDFAppearanceMode" withDefault:PSPDFAppearanceModeDefault];

    [_pdfController.appearanceModeManager setAppearanceMode:value];

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:(int)_pdfController.appearanceModeManager.appearanceMode] callbackId:command.callbackId];
}

#pragma mark Cache

- (void)clearCache:(CDVInvokedUrlCommand *)command {
    [PSPDFKit.sharedInstance.cache clearCache];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}

- (void)removeCacheForPresentedDocument:(CDVInvokedUrlCommand *)command {
    [PSPDFKit.sharedInstance.cache removeCacheForDocument:_pdfDocument];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}

#pragma mark Paging

- (void)setPage:(CDVInvokedUrlCommand *)command
{
    NSInteger page = [[command argumentAtIndex:0 withDefault:@(NSNotFound)] integerValue];
    BOOL animated = [[command argumentAtIndex:1 withDefault:@NO] boolValue];

    if (page != NSNotFound) {
        [_pdfController setPageIndex:page animated:animated];
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                    callbackId:command.callbackId];
    }
    else {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"'page' argument was null"] callbackId:command.callbackId];
    }
}

- (void)getPage:(CDVInvokedUrlCommand *)command
{
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:(int)_pdfController.pageIndex] callbackId:command.callbackId];
}

- (void)getPageCount:(CDVInvokedUrlCommand *)command
{
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:(int)_pdfDocument.pageCount] callbackId:command.callbackId];
}

- (void)scrollToNextPage:(CDVInvokedUrlCommand *)command
{
    BOOL animated = [[command argumentAtIndex:0 withDefault:@NO] boolValue];
    [_pdfController.documentViewController scrollToNextSpreadAnimated:animated];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

- (void)scrollToPreviousPage:(CDVInvokedUrlCommand *)command
{
    BOOL animated = [[command argumentAtIndex:0 withDefault:@NO] boolValue];
    [_pdfController.documentViewController scrollToNextSpreadAnimated:animated];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

#pragma mark Toolbar Items

- (void)setLeftBarButtonItems:(CDVInvokedUrlCommand *)command
{
    NSArray *items = [command argumentAtIndex:0 withDefault:@[]];
    [self setOptionsWithDictionary:@{@"leftBarButtonItems": items} animated:NO];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

- (void)setRightBarButtonItems:(CDVInvokedUrlCommand *)command
{
    NSArray *items = [command argumentAtIndex:0 withDefault:@[]];
    [self setOptionsWithDictionary:@{@"rightBarButtonItems": items} animated:NO];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

#pragma mark Annotation Toolbar methods

- (void)hideAnnotationToolbar:(CDVInvokedUrlCommand *)command
{
    [_pdfController.annotationToolbarController updateHostView:nil container:nil viewController:_pdfController];
    [_pdfController.annotationToolbarController hideToolbarAnimated:YES];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

- (void)showAnnotationToolbar:(CDVInvokedUrlCommand *)command
{
    // Must be in document view mode when showing annotation toolbar
    [_pdfController setViewMode:PSPDFViewModeDocument animated:YES];

    [_pdfController.annotationToolbarController updateHostView:nil container:nil viewController:_pdfController];
    [_pdfController.annotationToolbarController showToolbarAnimated:YES];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

- (void)toggleAnnotationToolbar:(CDVInvokedUrlCommand *)command
{
    // Must be in document view mode when showing annotation toolbar
    [_pdfController setViewMode:PSPDFViewModeDocument animated:YES];

    [_pdfController.annotationToolbarController updateHostView:nil container:nil viewController:_pdfController];
    [_pdfController.annotationToolbarController toggleToolbarAnimated:YES];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

#pragma mark Delegate methods

- (void)pdfViewController:(PSPDFViewController *)pdfController willBeginDisplayingPageView:(PSPDFPageView *)pageView forPageAtIndex:(NSInteger)pageIndex
{
    [self sendEventWithJSON:[NSString stringWithFormat:@"{type:'willBeginDisplayingPageView',page:%ld}", (long) pageIndex]];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didFinishRenderTaskForPageView:(PSPDFPageView *)pageView
{
    [self sendEventWithJSON:[NSString stringWithFormat:@"{type:'didFinishRenderTaskForPageView',page:%ld}", (long) pageView.pageIndex]];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didConfigurePageView:(PSPDFPageView *)pageView forPageAtIndex:(NSInteger)pageIndex
{
    [self sendEventWithJSON:[NSString stringWithFormat:@"{type:'didConfigurePageView',page:%ld}", (long) pageView.pageIndex]];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didCleanupPageView:(PSPDFPageView *)pageView forPageAtIndex:(NSInteger)pageIndex
{
    [self sendEventWithJSON:[NSString stringWithFormat:@"{type:'didCleanupPageView',page:%ld}", (long) pageView.pageIndex]];
}

- (BOOL)pdfViewController:(PSPDFViewController *)pdfController didTapOnPageView:(PSPDFPageView *)pageView atPoint:(CGPoint)viewPoint
{
    // inverted because it's almost always YES (due to handling JS eval calls).
    // in order to set this event as handled use explicit "return false;" in JS callback.
    return ![self sendEventWithJSON:[NSString stringWithFormat:@"{type:'didTapOnPageView',viewPoint:[%g,%g]}", viewPoint.x, viewPoint.y]];
}

- (BOOL)pdfViewController:(PSPDFViewController *)pdfController didLongPressOnPageView:(PSPDFPageView *)pageView atPoint:(CGPoint)viewPoint gestureRecognizer:(UILongPressGestureRecognizer *)gestureRecognizer
{
    // inverted because it's almost always YES (due to handling JS eval calls).
    // in order to set this event as handled use explicit "return false;" in JS callback.
    return ![self sendEventWithJSON:[NSString stringWithFormat:@"{type:'didLongPressOnPageView',viewPoint:[%g,%g]}", viewPoint.x, viewPoint.y]];
}

static NSString *PSPDFStringFromCGRect(CGRect rect) {
    return [NSString stringWithFormat:@"[%g,%g,%g,%g]", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
}

- (BOOL)pdfViewController:(PSPDFViewController *)pdfController shouldSelectText:(NSString *)text withGlyphs:(NSArray *)glyphs atRect:(CGRect)rect onPageView:(PSPDFPageView *)pageView
{
    return [self sendEventWithJSON:@{@"type": @"shouldSelectText", @"text": text, @"rect": PSPDFStringFromCGRect(rect)}];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didSelectText:(NSString *)text withGlyphs:(NSArray *)glyphs atRect:(CGRect)rect onPageView:(PSPDFPageView *)pageView
{
    [self sendEventWithJSON:@{@"type": @"didSelectText", @"text": text, @"rect": PSPDFStringFromCGRect(rect)}];
}

- (void)pdfViewControllerWillDismiss:(PSPDFViewController *)pdfController
{
    [self sendEventWithJSON:@"{type:'willDismiss'}"];
}

- (void)pdfViewControllerDidDismiss:(PSPDFViewController *)pdfController
{
    //release the pdf document and controller
    _pdfDocument = nil;
    _pdfController = nil;
    _navigationController = nil;
    
    //send event
    [self sendEventWithJSON:@"{type:'didDismiss'}"];
}

- (BOOL)pdfViewController:(PSPDFViewController *)pdfController shouldShowUserInterface:(BOOL)animated
{
    return [self sendEventWithJSON:@{@"type": @"shouldShowUserInterface", @"animated": @(animated)}];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didShowUserInterface:(BOOL)animated
{
    [self sendEventWithJSON:@{@"type": @"didShowUserInterface", @"animated": @(animated)}];
}

- (BOOL)pdfViewController:(PSPDFViewController *)pdfController shouldHideUserInterface:(BOOL)animated
{
    return [self sendEventWithJSON:@{@"type": @"shouldHideUserInterface", @"animated": @(animated)}];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didHideUserInterface:(BOOL)animated
{
    [self sendEventWithJSON:@{@"type": @"didHideUserInterface", @"animated": @(animated)}];
}

#pragma mark Annotation toolbar delegate methods

- (void)flexibleToolbarContainerDidShow:(nonnull PSPDFFlexibleToolbarContainer *)container {
    [self sendEventWithJSON:@"{type:'flexibleToolbarContainerDidShow'}"];
}

- (void)flexibleToolbarContainerDidHide:(nonnull PSPDFFlexibleToolbarContainer *)container {
    [self sendEventWithJSON:@"{type:'flexibleToolbarContainerDidHide'}"];
} 

- (CGRect)flexibleToolbarContainerContentRect:(PSPDFFlexibleToolbarContainer *)container forToolbarPosition:(PSPDFFlexibleToolbarPosition)position {
    // This is a workaround for handling the positioning of the annotation toolbar so that it's not covered by the components of the safe area.
    // It is recommended that one calculates the positioning of the toolbar with respect to their own views.
    PSPDFViewController *controller = self.pdfController;
    if ([controller respondsToSelector:@selector(flexibleToolbarContainerContentRect:forToolbarPosition:)]) {
        return [controller flexibleToolbarContainerContentRect:container forToolbarPosition:position];
    }
    return container.bounds;
}

@end
