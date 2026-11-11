/**
 * Hyperloop iOS-Core
 * Copyright (c) 2015-present by Appcelerator, Inc.
 */

#import <XCTest/XCTest.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "HyperloopModule.h"
#import "pointer.h"
#import "class.h"
#import "utils.h"
#import <dlfcn.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

static id KrollValue;
static JSClassRef classDef;

/*
 * Test-only ownership tracking for the JSStringRef copies made by HyperloopModule.m, which is
 * linked into this bundle from libhyperloop.a. The static linker binds the module's calls to these definitions
 * instead of the JavaScriptCore exports; both forward to JavaScriptCore. While tracking is
 * active, every non-NULL JSValueToStringCopy result must be released exactly once.
 * trackedJSStrings counts outstanding acquisitions per address. Each acquisition is pinned by an
 * extra JSStringRetain until tracking stops, so a tracked address cannot be reused by an unrelated
 * JSStringRef during the interval and a release at zero outstanding is a genuine extra release.
 */
static CFMutableBagRef trackedJSStrings = NULL;
static CFMutableSetRef acquiredJSStrings = NULL;
static CFMutableArrayRef pinnedJSStrings = NULL;
static NSUInteger trackedJSStringCopies = 0;
static NSUInteger trackedJSStringDoubleReleases = 0;

static void *JavaScriptCoreSymbol (const char *name) {
	static void *handle = NULL;
	if (handle == NULL) {
		Dl_info info;
		if (dladdr((const void *)JSStringCreateWithUTF8CString, &info) == 0 || info.dli_fname == NULL ||
			(handle = dlopen(info.dli_fname, RTLD_LAZY | RTLD_NOLOAD)) == NULL) {
			fprintf(stderr, "cannot locate the loaded JavaScriptCore image\n");
			abort();
		}
	}
	void *symbol = dlsym(handle, name);
	if (symbol == NULL) {
		fprintf(stderr, "cannot resolve JavaScriptCore symbol %s: %s\n", name, dlerror());
		abort();
	}
	return symbol;
}

JSStringRef JSValueToStringCopy (JSContextRef ctx, JSValueRef value, JSValueRef *exception) {
	static JSStringRef (*copy)(JSContextRef, JSValueRef, JSValueRef *) = NULL;
	if (copy == NULL) {
		copy = (JSStringRef (*)(JSContextRef, JSValueRef, JSValueRef *))JavaScriptCoreSymbol("JSValueToStringCopy");
	}
	JSStringRef string = copy(ctx, value, exception);
	if (trackedJSStrings && string) {
		CFBagAddValue(trackedJSStrings, string);
		CFSetAddValue(acquiredJSStrings, string);
		CFArrayAppendValue(pinnedJSStrings, JSStringRetain(string));
		trackedJSStringCopies++;
	}
	return string;
}

void JSStringRelease (JSStringRef string) {
	static void (*release)(JSStringRef) = NULL;
	if (release == NULL) {
		release = (void (*)(JSStringRef))JavaScriptCoreSymbol("JSStringRelease");
	}
	if (trackedJSStrings && string) {
		if (CFBagGetCountOfValue(trackedJSStrings, string) > 0) {
			CFBagRemoveValue(trackedJSStrings, string);
		} else if (CFSetContainsValue(acquiredJSStrings, string)) {
			trackedJSStringDoubleReleases++;
		}
	}
	release(string);
}

static void StopTrackingJSStrings (void) {
	if (trackedJSStrings == NULL) {
		return;
	}
	CFMutableArrayRef pinned = pinnedJSStrings;
	CFRelease(trackedJSStrings);
	CFRelease(acquiredJSStrings);
	trackedJSStrings = NULL;
	acquiredJSStrings = NULL;
	pinnedJSStrings = NULL;
	// tracking is off, so these releases forward without being counted
	for (CFIndex i = 0; i < CFArrayGetCount(pinned); i++) {
		JSStringRelease((JSStringRef)CFArrayGetValueAtIndex(pinned, i));
	}
	CFRelease(pinned);
}

static void StartTrackingJSStrings (void) {
	StopTrackingJSStrings();
	trackedJSStrings = CFBagCreateMutable(NULL, 0, NULL);
	acquiredJSStrings = CFSetCreateMutable(NULL, 0, NULL);
	pinnedJSStrings = CFArrayCreateMutable(NULL, 0, NULL);
	trackedJSStringCopies = 0;
	trackedJSStringDoubleReleases = 0;
}

static NSString *NSStringFromJSValueRef (JSContextRef ctx, JSValueRef value, JSValueRef *exception) {
	JSStringRef string = JSValueToStringCopy(ctx, value, exception);
	size_t len = JSStringGetMaximumUTF8CStringSize(string);
	char *s = malloc(len);
	len = JSStringGetUTF8CString(string, s, len);
	NSString *str = [NSString stringWithUTF8String:s];
	free(s);
	JSStringRelease(string);
	return str;
}

@class KrollCallback;

id JSValueRefToId (JSContextRef ctx, const JSValueRef value, JSValueRef *exception);
void HyperloopRegisterCallbackForIdentifier (KrollCallback *callback, NSString *identifier);

JSObjectRef ConstructorCallback (JSContextRef ctx, JSObjectRef constructor, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception) {
	id obj = JSValueRefToId(ctx, arguments[0], exception);
	return JSObjectMake(ctx, classDef, (__bridge void *)(obj));
}

JSValueRef FunctionCallback (JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception) {
	id obj = JSValueRefToId(ctx, arguments[0], exception);
	return JSObjectMake(ctx, classDef, (__bridge void *)(obj));
}

JSValueRef KrollCallbackFunction (JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception) {
	return JSValueMakeNumber(ctx, 123);
}

@interface KrollContext : NSObject
@property (assign) JSGlobalContextRef context;
@end

@interface KrollBridge : NSObject
@end

@interface KrollCallback : NSObject

@property (retain) NSArray * args;
@property (retain) id thisObject;
@property (retain) id result;
@property (assign) BOOL called;
@property (assign) JSObjectRef function;

-(id)call:(NSArray *)args thisObject:(id)this;

@end

@implementation KrollContext
@end

@implementation KrollBridge
@end

@implementation KrollCallback
-(id)call:(NSArray *)args_ thisObject:(id)thisObject_ {
	_args = args_;
	_thisObject = thisObject_;
	_called = YES;
	return _result;
}
@end

@interface KrollObject : NSObject
+(id)toID:(KrollContext *)c value:(JSValueRef)ref;
@end

@implementation KrollObject
+(id)toID:(KrollContext *)c value:(JSValueRef)ref {
	return KrollValue;
}
@end

static int TestJSReceivedLeading;
static unsigned int TestJSReceivedUnsigned;
static int TestJSReceivedTrailing;

@interface TestJSExample : NSObject
@end

@implementation TestJSExample
+(unsigned long long)testUnsignedIntArg:(unsigned int)value {
	return value;
}
+(void)testLeading:(int)leading unsignedInt:(unsigned int)value trailing:(int)trailing {
	TestJSReceivedLeading = leading;
	TestJSReceivedUnsigned = value;
	TestJSReceivedTrailing = trailing;
}
+(int)testInt {
	return 2;
}
+(void)testDoubleArg:(NSTimeInterval)duration {
	if (duration != 12.3) {
		@throw [NSException exceptionWithName:@"InvalidArg" reason:@"time should have been 12.3" userInfo:nil];
	}
}
+(uintptr_t)addressOfPointer:(void *)pointer {
	return (uintptr_t)pointer;
}
@end

// Fixture defined in TestDispatch.m. Its selectors return 0 for nil, 1 for a non-nil
// empty NSArray, 2 for a non-empty NSArray and 3 for any other object.
@interface TestArrayArgumentMock : NSObject
+(void)reset;
+(id)receivedValue;
+(int)receivedBefore;
+(int)receivedAfter;
+(int)enteredCount;
@end

@interface TestJS : XCTestCase

@property (nonatomic, retain) KrollContext *ctx;
@property (nonatomic, retain) KrollBridge *bridge;
@property (nonatomic, assign) JSObjectRef global;
@property (nonatomic, assign) JSContextGroupRef group;

@end

@implementation TestJS

-(void)setUp {
	_ctx = [KrollContext new];
	_bridge = [KrollBridge new];
	_group = JSContextGroupCreate();
	_ctx.context = JSGlobalContextCreateInGroup(_group, NULL);
	[Hyperloop willStartNewContext:_ctx bridge:_bridge];
	_global = JSContextGetGlobalObject(_ctx.context);
	[Hyperloop didStartNewContext:_ctx bridge:_bridge];
	
}

-(void)tearDown {
	StopTrackingJSStrings();
	[TestArrayArgumentMock reset];
	[Hyperloop willStopNewContext:_ctx bridge:_bridge];
	JSGlobalContextRelease(_ctx.context);
	JSContextGroupRelease(_group);
	[Hyperloop didStopNewContext:_ctx bridge:_bridge];
	_ctx.context = nil;
	_global = nil;
	_group = nil;
	_ctx = nil;
	KrollValue = nil;
	_bridge = nil;
#ifdef HYPERLOOP_MEMORY_TRACKING
	HyperloopTrackDumpAll();
#endif
}

-(void)testCreateGlobal {
	JSStringRef prop = JSStringCreateWithUTF8CString("Hyperloop");
	XCTAssertTrue(JSObjectHasProperty(_ctx.context, _global, prop));
	JSValueRef exception = NULL;
	JSValueRef hyperloop = JSObjectGetProperty(_ctx.context, _global, prop, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertTrue(JSValueIsObject(_ctx.context, hyperloop));
	JSObjectRef hyperloopRef = JSValueToObject(_ctx.context, hyperloop, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(prop);
	prop = JSStringCreateWithUTF8CString("createProxy");
	XCTAssertTrue(JSObjectHasProperty(_ctx.context, hyperloopRef, prop));
	XCTAssertTrue(JSObjectIsFunction(_ctx.context, JSValueToObject(_ctx.context, JSObjectGetProperty(_ctx.context, hyperloopRef, prop, &exception), &exception)));
	XCTAssertTrue(exception == NULL);
	JSStringRelease(prop);
	prop = JSStringCreateWithUTF8CString("createPointer");
	XCTAssertTrue(JSObjectHasProperty(_ctx.context, hyperloopRef, prop));
	XCTAssertTrue(JSObjectIsFunction(_ctx.context, JSValueToObject(_ctx.context, JSObjectGetProperty(_ctx.context, hyperloopRef, prop, &exception), &exception)));
	XCTAssertTrue(exception == NULL);
	JSStringRelease(prop);
	prop = JSStringCreateWithUTF8CString("dispatch");
	XCTAssertTrue(JSObjectHasProperty(_ctx.context, hyperloopRef, prop));
	XCTAssertTrue(JSObjectIsFunction(_ctx.context, JSValueToObject(_ctx.context, JSObjectGetProperty(_ctx.context, hyperloopRef, prop, &exception), &exception)));
	XCTAssertTrue(exception == NULL);
	JSStringRelease(prop);
	prop = JSStringCreateWithUTF8CString("Hyperloop");
	JSObjectDeleteProperty(_ctx.context, _global, prop, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(prop);
}

-(void)testCreateClass {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("var p = Hyperloop.createProxy({class:'NSObject', alloc:false, init:'class', args:null}); Hyperloop.dispatch(p, 'description');");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsObject(_ctx.context, result));
	id p = (__bridge id)JSObjectGetPrivate(JSValueToObject(_ctx.context, result, &exception));
	XCTAssertTrue(exception == NULL);
	XCTAssertTrue([p isKindOfClass:[HyperloopPointer class]]);
	NSString *resultStr = NSStringFromJSValueRef(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertTrue([resultStr isEqual:@"NSObject"]);
}

-(void)testCreateDictionary {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("var a = {'a':1}; a");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsObject(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSDictionary class]]);
	XCTAssertEqualObjects(obj, @{@"a":@1});
}

-(void)testCreateString {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("'foo'");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsString(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSString class]]);
	XCTAssertEqualObjects(obj, @"foo");
}

-(void)testCreateNumber {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("123");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsNumber(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSNumber class]]);
	XCTAssertEqualObjects(obj, @123);
}

-(void)testCreateBool {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("true");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsBoolean(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSNumber class]]);
	XCTAssertEqualObjects(obj, @YES);
}

-(void)testCreateUndefined {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("undefined");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsUndefined(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSNull class]]);
	XCTAssertEqualObjects(obj, [NSNull null]);
}

-(void)testCreateNull {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("null");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsNull(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSNull class]]);
	XCTAssertEqualObjects(obj, [NSNull null]);
}

-(void)testCreateDate {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("new Date()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsDate(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSDate class]]);
	XCTAssertEqualObjects([obj description], [[NSDate date] description]);
}

-(void)testCreateArray {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("[1, 2, 3]");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsObject(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSArray class]]);
	id check = @[
		@1,
		@2,
		@3
	];
	XCTAssertEqualObjects(obj, check);
}

-(void)testCreateClassInDictionary {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("(function() {var p = Hyperloop.createProxy({class:'NSObject', alloc:false, init:'class', args:null}); return {'c':p}})()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsObject(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSDictionary class]]);
	id p = [obj objectForKey:@"c"];
	XCTAssertNotNil(p);
	XCTAssertTrue([p isKindOfClass:[HyperloopClass class]]);
}

-(void)testCreateClassInArray {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("(function() {var p = Hyperloop.createProxy({class:'NSObject', alloc:false, init:'class', args:null}); return [p] })()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsObject(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSArray class]]);
	id p = [obj objectAtIndex:0];
	XCTAssertNotNil(p);
	XCTAssertTrue([p isKindOfClass:[HyperloopClass class]]);
}


-(void)testCreatePointerInDictionary {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("(function() {var p = Hyperloop.createPointer('d'); return {'a':p} })()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsObject(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSDictionary class]]);
	id p = [obj objectForKey:@"a"];
	XCTAssertNotNil(p);
	XCTAssertTrue([p isKindOfClass:[HyperloopPointer class]]);
	XCTAssertEqualObjects([p description], @"0.000000");
	XCTAssertEqual([p intValue], 0);
}

-(void)testCreatePointerInArray {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("(function() {var p = Hyperloop.createPointer('d'); return [p] })()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsObject(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSArray class]]);
	id p = [obj objectAtIndex:0];
	XCTAssertNotNil(p);
	XCTAssertTrue([p isKindOfClass:[HyperloopPointer class]]);
	XCTAssertEqualObjects([p description], @"0.000000");
	XCTAssertEqual([p intValue], 0);
}

-(void)testCreatePointerConvertToString {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("(function() {var p = Hyperloop.createPointer('d'); return String(p) })()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsString(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSString class]]);
	XCTAssertEqualObjects(obj, @"0.000000");
}

-(void)testIsNullPointer {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("(function() {var p = Hyperloop.createPointer('d'); return Hyperloop.isNull(p) })()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsBoolean(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSNumber class]]);
	XCTAssertEqualObjects(obj, @NO);
}

-(void)testProtectUnprotect {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("(function() {var p = Hyperloop.createPointer('d'); return Hyperloop.protect(p) && Hyperloop.unprotect(p); })()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsBoolean(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSNumber class]]);
	XCTAssertEqualObjects(obj, @YES);
}

-(void)testConvertToInt {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("(function() {var p = Hyperloop.createPointer('d'); return Hyperloop.intValue(p) })()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsNumber(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSNumber class]]);
	XCTAssertEqualObjects(obj, @0);
}

-(void)testConvertToIntWithValue {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("(function() {var p = Hyperloop.createPointer('i'); Hyperloop.dispatch(p, 'setValue:atIndex:', [123, 0]); return Hyperloop.intValue(p) })()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsNumber(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSNumber class]]);
	XCTAssertEqualObjects(obj, @123);
}

-(void)testConvertToIntAsString {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("(function() {var p = Hyperloop.createPointer('i'); Hyperloop.dispatch(p, 'setValue:atIndex:', [123, 0]); return Hyperloop.stringValue(p) })()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsString(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSString class]]);
	XCTAssertEqualObjects(obj, @"123");
}

// the typed JS accessors convert a pointer's stored value into the requested type
-(void)testConvertPointerValueBetweenTypes {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("(function() {var d = Hyperloop.createPointer('d'); Hyperloop.dispatch(d, 'setValue:atIndex:', [-3.75, 0]); var i = Hyperloop.createPointer('i'); Hyperloop.dispatch(i, 'setValue:atIndex:', [123, 0]); return [Hyperloop.intValue(d), Hyperloop.boolValue(d), Hyperloop.doubleValue(d), Hyperloop.doubleValue(i), Hyperloop.floatValue(i)] })()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertTrue([obj isKindOfClass:[NSArray class]]);
	XCTAssertEqualObjects(obj, (@[@-3, @YES, @-3.75, @123, @123]));
}

-(void)testJSStringAsString {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("Hyperloop.stringValue('hello')");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsString(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSString class]]);
	XCTAssertEqualObjects(obj, @"hello");
}

-(void)testJSBooleanTrueAsString {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("Hyperloop.stringValue(true)");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsString(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSString class]]);
	XCTAssertEqualObjects(obj, @"true");
}

-(void)testJSBooleanFalseAsString {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("Hyperloop.stringValue(false)");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsString(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSString class]]);
	XCTAssertEqualObjects(obj, @"false");
}

-(void)testJSNumberAsString {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("Hyperloop.stringValue(123)");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsString(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSString class]]);
	XCTAssertEqualObjects(obj, @"123");
}

-(void)testJSBooleanTrueAsBool {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("Hyperloop.boolValue(true)");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsBoolean(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSNumber class]]);
	XCTAssertEqualObjects(obj, @YES);
}

-(void)testJSBooleanFalseAsBool {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("Hyperloop.boolValue(false)");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsBoolean(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSNumber class]]);
	XCTAssertEqualObjects(obj, @NO);
}

-(void)testJSFunctionAsString {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("function F() {}; F");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsObject(_ctx.context, result));
	KrollValue = [KrollCallback new];
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[KrollCallback class]]);
}

-(void)testJSRegExAsNSRegularExpression {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("/a/i");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRelease(script);
	XCTAssertTrue(JSValueIsObject(_ctx.context, result));
	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSRegularExpression class]]);
	NSRegularExpression *re = (NSRegularExpression *)obj;
	XCTAssertTrue(([re options] & NSRegularExpressionCaseInsensitive) == NSRegularExpressionCaseInsensitive);
	XCTAssertTrue(([re options] & NSRegularExpressionAnchorsMatchLines) != NSRegularExpressionAnchorsMatchLines);
}

-(void)testException {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("Hyperloop.dispatch()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception != NULL);
	XCTAssertTrue(result == NULL);
	XCTAssertTrue(JSValueIsObject(_ctx.context, exception));
	id obj = JSValueRefToId(_ctx.context, exception, NULL);
	XCTAssertNotNil(obj);
	XCTAssertTrue([obj isKindOfClass:[NSDictionary class]]);
	XCTAssertEqualObjects([obj objectForKey:@"column"], @19);
	XCTAssertEqualObjects([obj objectForKey:@"line"], @1);
	XCTAssertEqualObjects([obj objectForKey:@"name"], @"InvalidArgument");
	XCTAssertEqualObjects([obj objectForKey:@"description"], @"you must pass at least 2 arguments to dispatch");
	XCTAssertEqualObjects([obj objectForKey:@"message"], @"you must pass at least 2 arguments to dispatch");
	id stack = [obj objectForKey:@"stack"];
	XCTAssertTrue([stack isKindOfClass:[NSString class]]);
	XCTAssertTrue([stack length] > 0);
	XCTAssertTrue([obj objectForKey:@"nativeStack"] != nil);
	JSStringRelease(script);
}

-(void)testExceptionLikeObjectGettersEvaluatedOnce {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString(
		"var counts = { line: 0, column: 0 };"
		"({ get line() { counts.line++; return 0; }, get column() { counts.column++; return 7; } })");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	JSStringRelease(script);
	XCTAssertTrue(exception == NULL);
	XCTAssertTrue(JSValueIsObject(_ctx.context, result));

	id obj = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertTrue([obj isKindOfClass:[NSDictionary class]]);
	XCTAssertEqualObjects([obj objectForKey:@"line"], @0);
	XCTAssertEqualObjects([obj objectForKey:@"column"], @7);

	script = JSStringCreateWithUTF8CString("[counts.line, counts.column]");
	JSValueRef counts = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	JSStringRelease(script);
	XCTAssertTrue(exception == NULL);
	id countsObj = JSValueRefToId(_ctx.context, counts, &exception);
	XCTAssertEqualObjects(countsObj, (@[@1, @1]));
}

-(void)testStruct {
	CGRect rect = CGRectMake(10, 20, 30, 40);
	HyperloopPointer *pointer = [HyperloopPointer pointer:&rect encoding:@encode(CGRect)];
	JSObjectRef object = [Hyperloop createPointer:pointer];
	JSStringRef prop = JSStringCreateWithUTF8CString("CGRect");
	JSValueRef exception = NULL;
	JSObjectSetProperty(_ctx.context, _global, prop, object, 0, &exception);
	XCTAssertTrue(exception == NULL);
	JSStringRef script = JSStringCreateWithUTF8CString("(function() { return {x: Hyperloop.dispatch(CGRect, 'valueAtIndex:', 0), y:Hyperloop.dispatch(CGRect, 'valueAtIndex:', 1), width:Hyperloop.dispatch(CGRect, 'valueAtIndex:', 2), height:Hyperloop.dispatch(CGRect, 'valueAtIndex:', 3) }; })()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertTrue(JSValueIsObject(_ctx.context, result));
	NSDictionary *dict = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	NSDictionary *expected = @{ @"x": @10, @"y": @20, @"width": @30, @"height": @40 };
	XCTAssertEqualObjects(dict, expected);
}

-(void)testPrimitiveReturnTypes {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("(function() { var cls = Hyperloop.createProxy({class:'TestJSExample', alloc:false, init:'class' }); return Hyperloop.dispatch(cls, 'testInt'); })()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertTrue(JSValueIsNumber(_ctx.context, result));
	XCTAssertEqual(2, JSValueToNumber(_ctx.context, result, &exception));
}

-(void)testPrimitiveArg {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString("(function() { var cls = Hyperloop.createProxy({class:'TestJSExample', alloc:false, init:'class' }); return Hyperloop.dispatch(cls, 'testDoubleArg:', 12.3); })()");
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertTrue(JSValueIsNull(_ctx.context, result));
}

-(void)testUnsignedIntNumberArg {
	NSMethodSignature *sig = [TestJSExample methodSignatureForSelector:@selector(testUnsignedIntArg:)];
	XCTAssertEqual(strcmp([sig getArgumentTypeAtIndex:2], "I"), 0);
	const unsigned int values[] = { 0u, 42u, (unsigned int)INT_MAX + 1u, UINT_MAX };
	for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); i++) {
		char source[256];
		snprintf(source, sizeof(source), "(function() { var cls = Hyperloop.createProxy({class:'TestJSExample', alloc:false, init:'class' }); return Hyperloop.dispatch(cls, 'testUnsignedIntArg:', %u); })()", values[i]);
		JSValueRef exception = NULL;
		JSStringRef script = JSStringCreateWithUTF8CString(source);
		JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
		JSStringRelease(script);
		XCTAssertTrue(exception == NULL);
		if (exception != NULL) {
			return;
		}
		XCTAssertTrue(result != NULL);
		if (result == NULL) {
			return;
		}
		XCTAssertTrue(JSValueIsNumber(_ctx.context, result));
		XCTAssertEqual(JSValueToNumber(_ctx.context, result, &exception), (double)values[i]);
	}
}

-(void)testUnsignedIntNumberArgBetweenArgs {
	const unsigned int values[] = { 0u, 42u, (unsigned int)INT_MAX + 1u, UINT_MAX };
	for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); i++) {
		TestJSReceivedLeading = 0;
		TestJSReceivedUnsigned = 0xDEADBEEFu;
		TestJSReceivedTrailing = 0;
		char source[256];
		snprintf(source, sizeof(source), "(function() { var cls = Hyperloop.createProxy({class:'TestJSExample', alloc:false, init:'class' }); return Hyperloop.dispatch(cls, 'testLeading:unsignedInt:trailing:', [-7, %u, 99]); })()", values[i]);
		JSValueRef exception = NULL;
		JSStringRef script = JSStringCreateWithUTF8CString(source);
		JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
		JSStringRelease(script);
		XCTAssertTrue(exception == NULL);
		if (exception != NULL) {
			return;
		}
		XCTAssertTrue(result != NULL);
		if (result == NULL) {
			return;
		}
		XCTAssertTrue(JSValueIsNull(_ctx.context, result));
		XCTAssertEqual(TestJSReceivedLeading, -7);
		XCTAssertEqual(TestJSReceivedUnsigned, values[i]);
		XCTAssertEqual(TestJSReceivedTrailing, 99);
	}
}

- (void)testKrollCallbackWithIdentifier {
	KrollCallback *callback = [[KrollCallback alloc] init];
	HyperloopRegisterCallbackForIdentifier(callback, @"123");
	JSStringRef name = JSStringCreateWithUTF8CString("callbackFunction");
	callback.function = JSObjectMakeFunctionWithCallback(_ctx.context, name, KrollCallbackFunction);
	JSStringRelease(name);
	id result = [HyperloopUtils invokeCustomCallback:@[] identifier:@"123" thisObject:nil];
	XCTAssertNotNil(result);
}

// a JS 0 or null passed to a pointer parameter arrives as NULL
-(void)testNullPointerArg {
	XCTAssertEqual(strcmp([[TestJSExample methodSignatureForSelector:@selector(addressOfPointer:)] getArgumentTypeAtIndex:2], "^v"), 0);
	const char *args[] = { "0", "null" };
	for (size_t i = 0; i < sizeof(args) / sizeof(args[0]); i++) {
		char source[256];
		snprintf(source, sizeof(source), "(function() { var cls = Hyperloop.createProxy({class:'TestJSExample', alloc:false, init:'class' }); return Hyperloop.dispatch(cls, 'addressOfPointer:', [%s]); })()", args[i]);
		JSValueRef exception = NULL;
		JSStringRef script = JSStringCreateWithUTF8CString(source);
		JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
		JSStringRelease(script);
		XCTAssertTrue(exception == NULL);
		if (exception != NULL) {
			return;
		}
		XCTAssertTrue(result != NULL);
		if (result == NULL) {
			return;
		}
		XCTAssertTrue(JSValueIsNumber(_ctx.context, result));
		XCTAssertEqual(JSValueToNumber(_ctx.context, result, &exception), 0.0);
	}
}

-(id)convertScript:(const char *)source exception:(JSValueRef *)exception {
	JSStringRef script = JSStringCreateWithUTF8CString(source);
	JSValueRef value = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, exception);
	JSStringRelease(script);
	XCTAssertTrue(*exception == NULL);
	return JSValueRefToId(_ctx.context, value, exception);
}

-(void)assertCyclicError:(JSValueRef)exception {
	XCTAssertTrue(exception != NULL);
	JSValueRef ignored = NULL;
	NSString *message = NSStringFromJSValueRef(_ctx.context, exception, &ignored);
	XCTAssertTrue([message containsString:@"cannot convert a cyclic object structure"], @"unexpected exception: %@", message);
}

-(void)testCyclicObjectThrows {
	JSValueRef exception = NULL;
	id obj = [self convertScript:"(function() { var o = { a: 1 }; o.self = o; return o; })()" exception:&exception];
	[self assertCyclicError:exception];
	XCTAssertEqualObjects(obj, [NSNull null]);
}

-(void)testCyclicArrayThrows {
	JSValueRef exception = NULL;
	id obj = [self convertScript:"(function() { var a = [1]; a.push(a); return a; })()" exception:&exception];
	[self assertCyclicError:exception];
	XCTAssertEqualObjects(obj, [NSNull null]);
}

-(void)testCyclicThroughNestedArrayThrows {
	JSValueRef exception = NULL;
	id obj = [self convertScript:"(function() { var parent = { children: [] }; parent.children.push({ parent: parent }); return parent; })()" exception:&exception];
	[self assertCyclicError:exception];
	XCTAssertEqualObjects(obj, [NSNull null]);
}

-(void)testCyclicThroughNativePropertyThrows {
	JSValueRef exception = NULL;
	id obj = [self convertScript:"(function() { var o = {}; o.$native = { back: o }; return o; })()" exception:&exception];
	[self assertCyclicError:exception];
	XCTAssertEqualObjects(obj, [NSNull null]);
}

-(void)testCyclicThroughErrorMessageThrows {
	JSValueRef exception = NULL;
	id obj = [self convertScript:"(function() { var o = { line: 1, column: 2 }; Object.defineProperty(o, 'message', { enumerable: false, get: function() { return { back: o }; } }); return o; })()" exception:&exception];
	[self assertCyclicError:exception];
	XCTAssertEqualObjects(obj, [NSNull null]);
}

-(void)testSharedReferenceConverts {
	JSValueRef exception = NULL;
	id obj = [self convertScript:"(function() { var x = { v: 1 }; return { a: x, b: [x, x] }; })()" exception:&exception];
	XCTAssertTrue(exception == NULL);
	XCTAssertTrue([obj isKindOfClass:[NSDictionary class]]);
	NSDictionary *expected = @{ @"v": @1 };
	XCTAssertEqualObjects(obj[@"a"], expected);
	NSArray *expectedArray = @[ expected, expected ];
	XCTAssertEqualObjects(obj[@"b"], expectedArray);
}

-(void)testCyclicObjectWithoutExceptionPointerConvertsBackEdgeToNull {
	JSStringRef script = JSStringCreateWithUTF8CString("(function() { var o = { a: 1 }; o.self = o; return o; })()");
	JSValueRef exception = NULL;
	JSValueRef value = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	JSStringRelease(script);
	XCTAssertTrue(exception == NULL);
	id obj = JSValueRefToId(_ctx.context, value, NULL);
	XCTAssertTrue([obj isKindOfClass:[NSDictionary class]]);
	XCTAssertEqualObjects(obj[@"a"], @1);
	XCTAssertEqualObjects(obj[@"self"], [NSNull null]);
}

-(void)assertTrackedJSStringsReleasedWithMinimumCopies:(NSUInteger)minimum {
	NSUInteger outstanding = trackedJSStrings ? (NSUInteger)CFBagGetCount(trackedJSStrings) : 0;
	NSUInteger copies = trackedJSStringCopies;
	NSUInteger doubleReleases = trackedJSStringDoubleReleases;
	StopTrackingJSStrings();
	XCTAssertGreaterThanOrEqual(copies, minimum, @"the tracked conversion path did not copy JSStringRefs");
	XCTAssertEqual(outstanding, (NSUInteger)0, @"%lu of %lu JSStringRef copies were not released", (unsigned long)outstanding, (unsigned long)copies);
	XCTAssertEqual(doubleReleases, (NSUInteger)0);
}

// converts a JS string in a separate context, then destroys that context before checking the NSString
-(void)assertStringConversionOfScript:(const char *)source expected:(NSString *)expected {
	JSGlobalContextRef ctx = JSGlobalContextCreate(NULL);
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString(source);
	JSValueRef value = JSEvaluateScript(ctx, script, NULL, NULL, 0, &exception);
	JSStringRelease(script);
	XCTAssertTrue(exception == NULL);
	if (exception != NULL || value == NULL) {
		XCTAssertTrue(value != NULL);
		JSGlobalContextRelease(ctx);
		return;
	}
	XCTAssertTrue(JSValueIsString(ctx, value));

	id converted = nil;
	@autoreleasepool {
		StartTrackingJSStrings();
		converted = JSValueRefToId(ctx, value, &exception);
		[self assertTrackedJSStringsReleasedWithMinimumCopies:1];
	}
	JSGlobalContextRelease(ctx);

	XCTAssertTrue(exception == NULL);
	XCTAssertTrue([converted isKindOfClass:[NSString class]]);
	XCTAssertEqual([converted length], [expected length]);
	XCTAssertEqualObjects(converted, expected);
}

-(void)testStringConversionReleasesJSString {
	[self assertStringConversionOfScript:"'hello'" expected:@"hello"];
	[self assertStringConversionOfScript:"''" expected:@""];
	[self assertStringConversionOfScript:"'caf\\u00e9 \\u65e5\\u672c \\uD83D\\uDE00'" expected:@"café 日本 \U0001F600"];
	XCTAssertEqual([@"\U0001F600" length], (NSUInteger)2);

	NSString *longASCII = [@"" stringByPaddingToLength:524288 withString:@"abcdefgh" startingAtIndex:0];
	[self assertStringConversionOfScript:"'abcdefgh'.repeat(65536)" expected:longASCII];
	NSString *longUnicode = [[@"" stringByPaddingToLength:65536 withString:@"é日" startingAtIndex:0] stringByAppendingString:@"\U0001F600"];
	[self assertStringConversionOfScript:"'\\u00e9\\u65e5'.repeat(32768) + '\\uD83D\\uDE00'" expected:longUnicode];
}

-(void)testDispatchSelectorConversionReleasesJSStrings {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString(
		"(function() {"
		"  var cls = Hyperloop.createProxy({class:'TestJSExample', alloc:false, init:'class' });"
		"  var sum = 0;"
		"  for (var i = 0; i < 100; i++) { sum += Hyperloop.dispatch(cls, 'testInt'); }"
		"  var fromObject = Hyperloop.dispatch(cls, { toString: function() { return 'testInt'; } });"
		"  return [sum, fromObject];"
		"})()");
	StartTrackingJSStrings();
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	[self assertTrackedJSStringsReleasedWithMinimumCopies:101];
	JSStringRelease(script);
	XCTAssertTrue(exception == NULL);
	if (exception != NULL) {
		return;
	}
	XCTAssertTrue(result != NULL);
	if (result == NULL) {
		return;
	}
	id values = JSValueRefToId(_ctx.context, result, &exception);
	XCTAssertTrue(exception == NULL);
	XCTAssertEqualObjects(values, (@[@200, @2]));
}

-(void)testDispatchSelectorToStringExceptionPropagates {
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString(
		"(function() {"
		"  var cls = Hyperloop.createProxy({class:'TestJSExample', alloc:false, init:'class' });"
		"  return Hyperloop.dispatch(cls, { toString: function() { throw new Error('selector failed'); } });"
		"})()");
	StartTrackingJSStrings();
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	[self assertTrackedJSStringsReleasedWithMinimumCopies:1];
	JSStringRelease(script);
	XCTAssertTrue(result == NULL);
	XCTAssertTrue(exception != NULL);
	if (exception == NULL) {
		return;
	}
	id error = JSValueRefToId(_ctx.context, exception, NULL);
	XCTAssertTrue([error isKindOfClass:[NSDictionary class]]);
	XCTAssertEqualObjects([error objectForKey:@"message"], @"selector failed");
}

// Evaluates Hyperloop.dispatch(TestArrayArgumentMock, selector, args) and returns the reported kind, or -1 on failure.
-(int)dispatchArrayFixture:(NSString *)selector args:(NSString *)args {
	[TestArrayArgumentMock reset];
	NSString *source = [NSString stringWithFormat:@"(function() { var c = Hyperloop.createProxy({class:'TestArrayArgumentMock', alloc:false, init:'class', args:null}); return Hyperloop.dispatch(c, '%@', %@, false); })()", selector, args];
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString([source UTF8String]);
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	JSStringRelease(script);
	XCTAssertTrue(exception == NULL);
	if (exception != NULL) {
		return -1;
	}
	XCTAssertTrue(result != NULL);
	if (result == NULL) {
		return -1;
	}
	XCTAssertTrue(JSValueIsNumber(_ctx.context, result));
	if (!JSValueIsNumber(_ctx.context, result)) {
		return -1;
	}
	return (int)JSValueToNumber(_ctx.context, result, NULL);
}

-(void)testDispatchEmptyJSArrayArgument {
	XCTAssertEqual([self dispatchArrayFixture:@"takeArray:" args:@"[[]]"], 1);
	id received = [TestArrayArgumentMock receivedValue];
	XCTAssertNotNil(received);
	XCTAssertTrue([received isKindOfClass:[NSArray class]]);
	XCTAssertEqual([received count], 0);
}

-(void)testDispatchNonEmptyJSArrayArgument {
	// Control: unchanged non-empty conversion path.
	XCTAssertEqual([self dispatchArrayFixture:@"takeArray:" args:@"[[1, 'two', [3]]]"], 2);
	id check = @[@1, @"two", @[@3]];
	XCTAssertEqualObjects([TestArrayArgumentMock receivedValue], check);
}

-(void)testDispatchNullObjectArgument {
	// Control: unchanged null path; JS null still arrives as nil.
	XCTAssertEqual([self dispatchArrayFixture:@"takeArray:" args:@"[null]"], 0);
	XCTAssertNil([TestArrayArgumentMock receivedValue]);
}

-(void)testDispatchNestedEmptyJSArrayArgument {
	XCTAssertEqual([self dispatchArrayFixture:@"takeArray:" args:@"[[[]]]"], 2);
	NSArray *received = [TestArrayArgumentMock receivedValue];
	XCTAssertEqual([received count], 1);
	if ([received count] != 1) {
		return;
	}
	id inner = received[0];
	XCTAssertNotNil(inner);
	XCTAssertTrue([inner isKindOfClass:[NSArray class]]);
	XCTAssertEqual([inner count], 0);
}

-(void)testDispatchEmptyJSArrayArgumentBetweenScalars {
	XCTAssertEqual([self dispatchArrayFixture:@"takeInt:array:int:" args:@"[7, [], 9]"], 1);
	id received = [TestArrayArgumentMock receivedValue];
	XCTAssertNotNil(received);
	XCTAssertTrue([received isKindOfClass:[NSArray class]]);
	XCTAssertEqual([received count], 0);
	XCTAssertEqual([TestArrayArgumentMock receivedBefore], 7);
	XCTAssertEqual([TestArrayArgumentMock receivedAfter], 9);
}

// Evaluates Hyperloop.dispatch(TestArrayArgumentMock, selector, args), catching in JS, and returns
// "error|<name>|<message>" for a thrown Error, "result|<value>" otherwise, or nil when evaluation fails.
-(NSString *)dispatchArrayFixtureOutcome:(NSString *)selector args:(NSString *)args {
	[TestArrayArgumentMock reset];
	NSString *source = [NSString stringWithFormat:@"(function() { var c = Hyperloop.createProxy({class:'TestArrayArgumentMock', alloc:false, init:'class', args:null}); try { return 'result|' + Hyperloop.dispatch(c, '%@', %@, false); } catch (e) { return (e instanceof Error ? 'error|' + e.name + '|' + e.message : 'thrown|' + e); } })()", selector, args];
	JSValueRef exception = NULL;
	JSStringRef script = JSStringCreateWithUTF8CString([source UTF8String]);
	JSValueRef result = JSEvaluateScript(_ctx.context, script, NULL, NULL, 0, &exception);
	JSStringRelease(script);
	XCTAssertTrue(exception == NULL);
	if (exception != NULL || result == NULL || !JSValueIsString(_ctx.context, result)) {
		XCTFail(@"dispatch of %@ did not produce an outcome string", selector);
		return nil;
	}
	return JSValueRefToId(_ctx.context, result, NULL);
}

-(void)testDispatchEmptyJSArrayToIntThrows {
	NSString *outcome = [self dispatchArrayFixtureOutcome:@"takeIntValue:" args:@"[[]]"];
	XCTAssertTrue([outcome hasPrefix:@"error|InvalidArgumentType|cannot convert argument type for ["], @"%@", outcome);
	XCTAssertTrue([outcome hasSuffix:@"at argument 0 (i)"], @"%@", outcome);
	XCTAssertEqual([TestArrayArgumentMock enteredCount], 0);
}

-(void)testDispatchEmptyJSArrayToClassThrows {
	NSString *outcome = [self dispatchArrayFixtureOutcome:@"takeClassValue:" args:@"[[]]"];
	XCTAssertTrue([outcome hasPrefix:@"error|InvalidArgumentType|"], @"%@", outcome);
	XCTAssertTrue([outcome hasSuffix:@"at argument 0 (#)"], @"%@", outcome);
	XCTAssertEqual([TestArrayArgumentMock enteredCount], 0);
}

-(void)testDispatchJSArraysToPointerThrow {
	for (NSString *args in @[@"[[]]", @"[[1, 2]]"]) {
		NSString *outcome = [self dispatchArrayFixtureOutcome:@"takePointer:" args:args];
		XCTAssertTrue([outcome hasPrefix:@"error|InvalidArgumentType|"], @"%@: %@", args, outcome);
		XCTAssertTrue([outcome hasSuffix:@"at argument 0 (^v)"], @"%@: %@", args, outcome);
		XCTAssertEqual([TestArrayArgumentMock enteredCount], 0, @"%@", args);
	}
}

-(void)testDispatchNonEmptyJSArrayToBlockThrows {
	NSString *outcome = [self dispatchArrayFixtureOutcome:@"takeBlockValue:" args:@"[[1, 2]]"];
	XCTAssertTrue([outcome hasPrefix:@"error|InvalidArgumentType|cannot convert argument type for ["], @"%@", outcome);
	XCTAssertTrue([outcome hasSuffix:@"at argument 0 (@?)"], @"%@", outcome);
	XCTAssertEqual([TestArrayArgumentMock enteredCount], 0);
}

-(void)testDispatchEmptyJSArrayToBlockStaysNil {
	// Unchanged compatibility control: [] to a block parameter still arrives as nil.
	XCTAssertEqualObjects([self dispatchArrayFixtureOutcome:@"takeBlockValue:" args:@"[[]]"], @"result|0");
	XCTAssertEqual([TestArrayArgumentMock enteredCount], 1);
}

-(void)testDispatchNullToBlockStaysNil {
	// Control: JS null to a block parameter still arrives as nil.
	XCTAssertEqualObjects([self dispatchArrayFixtureOutcome:@"takeBlockValue:" args:@"[null]"], @"result|0");
	XCTAssertEqual([TestArrayArgumentMock enteredCount], 1);
}

-(void)testDispatchNullToPointerStillAccepted {
	// Control: JS null to a pointer parameter is unaffected and arrives as NULL.
	XCTAssertEqualObjects([self dispatchArrayFixtureOutcome:@"takePointer:" args:@"[null]"], @"result|0");
	XCTAssertEqual([TestArrayArgumentMock enteredCount], 1);
}

-(void)testDispatchEmptyJSArrayToQualifiedObjectArgument {
	XCTAssertEqualObjects([self dispatchArrayFixtureOutcome:@"takeQualifiedArray:" args:@"[[]]"], @"result|1");
	id received = [TestArrayArgumentMock receivedValue];
	XCTAssertTrue([received isKindOfClass:[NSArray class]]);
	XCTAssertEqual([received count], 0);
}

@end

#pragma clang diagnostic pop
