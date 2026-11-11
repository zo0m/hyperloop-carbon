/**
 * Hyperloop iOS-Core
 * Copyright (c) 2015-present by Appcelerator, Inc.
 */

#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "pointer.h"
#import "class.h"
#import "utils.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

static int testObjectDealloc = 0;

@interface TestCleanupObject : NSObject
@end

@implementation TestCleanupObject
-(void)dealloc {
	testObjectDealloc++;
}
@end

@interface TestPointers : XCTestCase

@end

@implementation TestPointers


-(void)testPointerNSString {
	@autoreleasepool {
		NSString *str = @"hello";
		HyperloopPointer *p = [HyperloopPointer pointer:(__bridge void *)str encoding:@encode(NSString *)];
		XCTAssertEqualObjects(str, [p stringValue]);
		XCTAssertEqualObjects(p, str);
	}
}

- (void)testPointerCharStar {
	@autoreleasepool {
		char *str = "abc";
		HyperloopPointer *p = [HyperloopPointer pointer:str encoding:@encode(char *)];
		id value = [p stringValue];
		XCTAssertEqualObjects(value, [NSString stringWithUTF8String:str]);
		NSUInteger len = [p length];
		XCTAssertEqual(len, strlen(str));
		value = [p valueAtIndex:0];
		XCTAssertEqualObjects(value, [NSNumber numberWithChar:'a']);
		len = [value length];
		XCTAssertEqual(len, 1);
		XCTAssertEqualObjects([value stringValue], @"a");
	}
}

- (void)testPointerCharStarStar {
	@autoreleasepool {
		char *str = "abc";
		HyperloopPointer *p = [HyperloopPointer pointer:&str encoding:@encode(char **)];
		id value = [p stringValue];
		XCTAssertTrue([value hasPrefix:@"[Pointer 0x"]);
		XCTAssertTrue([value hasSuffix:@"^*]"]);
		id result = [p valueAtIndex:0];
		XCTAssertTrue([result isKindOfClass:[HyperloopPointer class]]);
		XCTAssertEqualObjects(result, [NSString stringWithUTF8String:str]);
		NSUInteger len = [result length];
		XCTAssertEqual(len, strlen(str));
		XCTAssertEqualObjects([result description], @"abc");
	}
}

- (void)testPointerInt {
	@autoreleasepool {
		int i = 123;
		HyperloopPointer *p = [HyperloopPointer pointer:&i encoding:@encode(int)];
		int value = [p intValue];
		XCTAssertEqual(value, i);
	}
}

// wraps a native int * that addresses a single 4-byte int. create:encoding: takes that address (as
// dispatch does for pointer returns); pointer:encoding: would instead copy a pointer-sized slot from
// it, reading 8 bytes from the 4-byte int.
- (void)testPointerIntStar {
	@autoreleasepool {
		int i = 123;
		int *ip = &i;
		HyperloopPointer *p = [HyperloopPointer create:ip encoding:@encode(int *)];
		XCTAssertEqual([p pointerValue], (void *)ip);
		id result = [p valueAtIndex:0];
		XCTAssertTrue([result isKindOfClass:[HyperloopPointer class]]);
		XCTAssertEqualObjects([result description], @"123");
		XCTAssertEqual([result intValue], i);
	}
}

- (void)testPointerSEL {
	@autoreleasepool {
		SEL sel = @selector(testPointerSEL);
		HyperloopPointer *p = [HyperloopPointer pointer:sel encoding:@encode(SEL)];
		id value = [p selectorValue];
		XCTAssertTrue([value isKindOfClass:[NSString class]]);
		XCTAssertEqualObjects(value, NSStringFromSelector(sel));
		XCTAssertEqualObjects([value description], NSStringFromSelector(sel));
		XCTAssertEqualObjects([p stringValue], NSStringFromSelector(sel));
	}
}

- (void)testPointerSELStar {
	@autoreleasepool {
		SEL sel = @selector(testPointerSEL);
		SEL *sp = &sel;
		HyperloopPointer *p = [HyperloopPointer pointer:sp encoding:@encode(SEL *)];
		id value = [p valueAtIndex:0];
		XCTAssertTrue([value isKindOfClass:[HyperloopPointer class]]);
		value = (HyperloopPointer*)value;
		id result = [value selectorValue];
		XCTAssertTrue([result isKindOfClass:[NSString class]]);
		XCTAssertEqualObjects(result, NSStringFromSelector(sel));
	}
}

- (void)testPointerID {
	@autoreleasepool {
		NSObject *o = [[NSObject alloc] init];
		HyperloopPointer *p = [HyperloopPointer pointer:(__bridge void *)(o) encoding:@encode(NSObject *)];
		id value = [p objectValue];
		XCTAssertTrue([value isKindOfClass:[NSObject class]]);
		XCTAssertEqualObjects(value, o);
		XCTAssertEqualObjects(p, o);
		XCTAssertEqualObjects([value description], [o description]);
		XCTAssertEqualObjects([p description], [o description]);
	}
}

- (void)testStruct {
	@autoreleasepool {
		CGRect rect = CGRectMake(10, 20, 30, 40);
		HyperloopPointer *p = [HyperloopPointer pointer:&rect encoding:@encode(CGRect)];
		id value = [p valueAtIndex:0];
		XCTAssertEqualObjects(value, @10);
		XCTAssertEqual([value intValue], 10);
		value = [p valueAtIndex:1];
		XCTAssertEqualObjects(value, @20);
		XCTAssertEqual([value intValue], 20);
		value = [p valueAtIndex:2];
		XCTAssertEqualObjects(value, @30);
		XCTAssertEqual([value intValue], 30);
		value = [p valueAtIndex:3];
		XCTAssertEqualObjects(value, @40);
		XCTAssertEqual([value intValue], 40);
		CGRect rp = *(CGRect *)[p pointerValue];
		XCTAssertTrue(CGRectEqualToRect(rp, rect));
	}
}

- (void)testIntArray {
	@autoreleasepool {
		int i [] = {1, 2, 3};
		HyperloopPointer *p = [HyperloopPointer pointer:i encoding:"[3i]"];
		id value = [p valueAtIndex:0];
		XCTAssertEqual([value intValue], 1);
		value = [p valueAtIndex:1];
		XCTAssertEqual([value intValue], 2);
		value = [p valueAtIndex:2];
		XCTAssertEqual([value intValue], 3);
	}
}

- (void)testCharArray {
	@autoreleasepool {
		char i [] = {'a', 'b', 'c'};
		HyperloopPointer *p = [HyperloopPointer pointer:i encoding:"[3c]"];
		id value = [p valueAtIndex:0];
		XCTAssertEqual([value charValue], 'a');
		value = [p valueAtIndex:1];
		XCTAssertEqual([value charValue], 'b');
		value = [p valueAtIndex:2];
		XCTAssertEqual([value charValue], 'c');
	}
}

- (void)testCharStarAsChar {
	@autoreleasepool {
		char *s = "abc";
		HyperloopPointer *p = [HyperloopPointer pointer:s encoding:"*"];
		id value = [p valueAtIndex:0];
		XCTAssertEqual([value charValue], 'a');
		value = [p valueAtIndex:1];
		XCTAssertEqual([value charValue], 'b');
		value = [p valueAtIndex:2];
		XCTAssertEqual([value charValue], 'c');
		char buf[4];
		[p getValue:0 pointer:&buf];
		XCTAssertTrue(buf[0] == 'a');
	}
}

- (void)testBoolArray {
	@autoreleasepool {
		bool i [] = {true, false, true};
		HyperloopPointer *p = [HyperloopPointer pointer:i encoding:"[3B]"];
		id value = [p valueAtIndex:0];
		XCTAssertEqual([value boolValue], true);
		value = [p valueAtIndex:1];
		XCTAssertEqual([value boolValue], false);
		value = [p valueAtIndex:2];
		XCTAssertEqual([value boolValue], true);
	}
}

- (void)testFloatArray {
	@autoreleasepool {
		float f [] = {1.0f, 1.1f, 1.2f};
		HyperloopPointer *p = [HyperloopPointer pointer:f encoding:"[3f]"];
		id value = [p valueAtIndex:0];
		XCTAssertEqual([value floatValue], 1.0f);
		value = [p valueAtIndex:1];
		XCTAssertEqual([value floatValue], 1.1f);
		value = [p valueAtIndex:2];
		XCTAssertEqual([value floatValue], 1.2f);
	}
}

- (void)testStringEquality {
	@autoreleasepool {
		NSString *hello = @"hello world";
		HyperloopPointer *p = [HyperloopPointer pointer:(__bridge const void *)(hello) encoding:@encode(NSString *)];
		XCTAssertEqualObjects(@"HELLO WORLD", [(NSString *)p uppercaseString]);
		XCTAssertEqualObjects(p, hello);
	}
}

- (void)testSetStructMember {
	@autoreleasepool {
		CGRect rect = CGRectMake(10,20,30,40);
		HyperloopPointer *p = [HyperloopPointer pointer:&rect encoding:@encode(CGRect)];
		XCTAssertEqualObjects([p valueAtIndex:0], @10);
		XCTAssertEqualObjects([p valueAtIndex:1], @20);
		XCTAssertEqualObjects([p valueAtIndex:2], @30);
		XCTAssertEqualObjects([p valueAtIndex:3], @40);
		[p setValue:@100 atIndex:0];
		[p setValue:@200 atIndex:1];
		[p setValue:@300 atIndex:2];
		[p setValue:@400 atIndex:3];
		XCTAssertEqualObjects([p valueAtIndex:0], @100);
		XCTAssertEqualObjects([p valueAtIndex:1], @200);
		XCTAssertEqualObjects([p valueAtIndex:2], @300);
		XCTAssertEqualObjects([p valueAtIndex:3], @400);
	}
}

- (void)testInt {
	@autoreleasepool {
		int i = 12234;
		HyperloopPointer *p = [HyperloopPointer pointer:&i encoding:@encode(int)];
		XCTAssertEqual([p intValue], i);
		XCTAssertEqualObjects([p stringValue], @"12234");
	}
}

- (void)testFloat {
	@autoreleasepool {
		float f = 1.2234;
		HyperloopPointer *p = [HyperloopPointer pointer:&f encoding:@encode(float)];
		XCTAssertEqual([p floatValue], f);
		XCTAssertEqualObjects([p stringValue], @"1.223400");
	}
}

- (void)testLong {
	@autoreleasepool {
		long l = 12234;
		HyperloopPointer *p = [HyperloopPointer pointer:&l encoding:@encode(long)];
		XCTAssertEqual([p longValue], l);
		XCTAssertEqualObjects([p stringValue], @"12234");
	}
}

- (void)testLongLong {
	@autoreleasepool {
		long long l = 122341234123234L;
		HyperloopPointer *p = [HyperloopPointer pointer:&l encoding:@encode(long long)];
		XCTAssertEqual([p longLongValue], l);
		XCTAssertEqualObjects([p stringValue], @"122341234123234");
	}
}

- (void)testUnsignedLong {
	@autoreleasepool {
		unsigned long l = (unsigned long)1L;
		HyperloopPointer *p = [HyperloopPointer pointer:&l encoding:@encode(unsigned long)];
		XCTAssertEqual([p unsignedLongValue], l);
		XCTAssertEqualObjects([p stringValue], @"1");
	}
}

- (void)testUnsignedLongLong {
	@autoreleasepool {
		unsigned long long l = 12234121234L;
		HyperloopPointer *p = [HyperloopPointer pointer:&l encoding:@encode(unsigned long long)];
		XCTAssertEqual([p unsignedLongLongValue], l);
		XCTAssertEqualObjects([p stringValue], @"12234121234");
	}
}

- (void)testDouble {
	@autoreleasepool {
		double d = 12234123412341234;
		HyperloopPointer *p = [HyperloopPointer pointer:&d encoding:@encode(double)];
		XCTAssertEqual([p doubleValue], d);
		XCTAssertEqualObjects([p stringValue], @"12234123412341234.000000");
	}
}

- (void)testShort {
	short s = 1;
	HyperloopPointer *p = [HyperloopPointer pointer:&s encoding:@encode(short)];
	XCTAssertEqual([p shortValue], s);
	XCTAssertEqualObjects([p stringValue], @"1");
}

- (void)testBool {
	@autoreleasepool {
		bool b = true;
		HyperloopPointer *p = [HyperloopPointer pointer:&b encoding:@encode(bool)];
		XCTAssertEqual([p boolValue], b);
		XCTAssertEqualObjects([p stringValue], @"true");
		XCTAssertEqual([p intValue], 1);
		[p setValue:@false atIndex:0];
		XCTAssertEqual([p boolValue], false);
		XCTAssertEqualObjects([p stringValue], @"false");
		XCTAssertEqual([p intValue], 0);
	}
}

- (void)testChar {
	@autoreleasepool {
		char a = 'a';
		HyperloopPointer *p = [HyperloopPointer pointer:&a encoding:@encode(char)];
		XCTAssertEqual([p charValue], a);
		XCTAssertEqualObjects([p stringValue], @"a");
		[p setValue:@'z' atIndex:0];
		XCTAssertEqual([p charValue], 'z');
		XCTAssertEqualObjects([p stringValue], @"z");
	}
}

- (void)testUnsignedChar {
	@autoreleasepool {
		unsigned char a = 'a';
		HyperloopPointer *p = [HyperloopPointer pointer:&a encoding:@encode(unsigned char)];
		XCTAssertEqual([p charValue], a);
		XCTAssertEqual([p unsignedCharValue], a);
		XCTAssertEqualObjects([p stringValue], @"a");
		[p setValue:@'z' atIndex:0];
		XCTAssertEqual([p charValue], 'z');
		XCTAssertEqual([p unsignedCharValue], 'z');
		XCTAssertEqualObjects([p stringValue], @"z");
	}
}

- (void)testID {
	@autoreleasepool {
		id v = @"hello";
		HyperloopPointer *p = [HyperloopPointer pointer:(__bridge const void *)(v) encoding:@encode(id)];
		XCTAssertEqualObjects([p objectValue], v);
		XCTAssertEqualObjects([p stringValue], v);
		XCTAssertEqualObjects(p, v);
	}
}

- (void)testClass {
	@autoreleasepool {
		Class v = [NSString class];
		HyperloopPointer *p = [HyperloopPointer pointer:(__bridge const void *)(v) encoding:@encode(Class)];
		XCTAssertEqual(object_getClassName([p classValue]), object_getClassName(v));
		XCTAssertEqualObjects([p stringValue], [NSString stringWithUTF8String:object_getClassName(v)]);
	}
}

- (void)testFloatStar {
	@autoreleasepool {
		float *f = malloc(sizeof(float)*2);
		HyperloopPointer *p = [HyperloopPointer create:f encoding:@encode(float *)];
		[p setValue:@1.2 atIndex:0];
		id result = [p valueAtIndex:0];
		XCTAssertEqual([result floatValue], 1.2f);
	}
}

- (void)testMixedSizeStruct {
	@autoreleasepool {
		void *s = malloc(sizeof(float) + sizeof(int) + sizeof(double) + sizeof(bool) + sizeof(char) + sizeof(SEL) + sizeof(id) + sizeof(Class));
		HyperloopPointer *p = [HyperloopPointer pointer:s encoding:"{fidBc:@#}"];
		free(s);
		[p setValue:@1.2 atIndex:0];
		[p setValue:@2 atIndex:1];
		[p setValue:@0.1112 atIndex:2];
		[p setValue:@true atIndex:3];
		[p setValue:@'a' atIndex:4];
		[p setValue:@"foo:" atIndex:5];
		[p setValue:@"hello" atIndex:6];
		[p setValue:[NSString class] atIndex:7];
		XCTAssertEqual([[p valueAtIndex:0] floatValue], 1.2f);
		XCTAssertEqual([[p valueAtIndex:1] intValue], 2);
		XCTAssertEqual([[p valueAtIndex:2] doubleValue], 0.1112);
		XCTAssertEqual([[p valueAtIndex:3] boolValue], true);
		XCTAssertEqual([[p valueAtIndex:4] charValue], 'a');
		XCTAssertEqualObjects([[p valueAtIndex:5] selectorValue], NSStringFromSelector(@selector(foo:)));
		XCTAssertEqualObjects([[p valueAtIndex:6] objectValue], @"hello");
		XCTAssertEqual([[p valueAtIndex:7] classValue], [NSString class]);

		float f;
		[p getValue:0 pointer:&f];
		XCTAssertEqual(f, 1.2f);

		int i;
		[p getValue:1 pointer:&i];
		XCTAssertEqual(i, 2);

		double d;
		[p getValue:2 pointer:&d];
		XCTAssertEqual(d, 0.1112);

		bool b;
		[p getValue:3 pointer:&b];
		XCTAssertEqual(b, true);

		char c;
		[p getValue:4 pointer:&c];
		XCTAssertEqual(c, 'a');

		SEL sel;
		[p getValue:5 pointer:&sel];
		XCTAssertEqual(sel, @selector(foo:));

		id obj;
		[p getValue:6 pointer:&obj];
		XCTAssertEqualObjects(obj, @"hello");

		Class cls;
		[p getValue:7 pointer:&cls];
		XCTAssertEqualObjects([NSString stringWithUTF8String:object_getClassName(cls)], NSStringFromClass(cls));
	}
}

- (void)testStructPointer {
	@autoreleasepool {

		HyperloopPointer *p = [HyperloopPointer encoding:"{^f}"];
		HyperloopPointer *st = [HyperloopPointer encoding:"{f}"];

		XCTAssertEqual([st floatValue], 0.0f);

		[st setValue:@1.2 atIndex:0];
		[p setValue:st atIndex:0];

		HyperloopPointer *ptr = nil;
		[p getValue:0 pointer:&ptr];

		XCTAssertEqual([[ptr valueAtIndex:0] floatValue], 1.2f);
	}
}

- (void)testEncodings {
	@autoreleasepool {
		XCTAssertEqualObjects([HyperloopPointer stringEncoding], [NSString stringWithUTF8String:@encode(char *)]);
		XCTAssertEqualObjects([HyperloopPointer charEncoding], [NSString stringWithUTF8String:@encode(char)]);
		XCTAssertEqualObjects([HyperloopPointer intEncoding], [NSString stringWithUTF8String:@encode(int)]);
		XCTAssertEqualObjects([HyperloopPointer doubleEncoding], [NSString stringWithUTF8String:@encode(double)]);
		XCTAssertEqualObjects([HyperloopPointer longEncoding], [NSString stringWithUTF8String:@encode(long)]);
		XCTAssertEqualObjects([HyperloopPointer longLongEncoding], [NSString stringWithUTF8String:@encode(long long)]);
		XCTAssertEqualObjects([HyperloopPointer shortEncoding], [NSString stringWithUTF8String:@encode(short)]);
		XCTAssertEqualObjects([HyperloopPointer boolEncoding], [NSString stringWithUTF8String:@encode(bool)]);
		XCTAssertEqualObjects([HyperloopPointer floatEncoding], [NSString stringWithUTF8String:@encode(float)]);
		XCTAssertEqualObjects([HyperloopPointer pointerEncoding], [NSString stringWithUTF8String:@encode(void *)]);
		XCTAssertEqualObjects([HyperloopPointer objectEncoding], [NSString stringWithUTF8String:@encode(id)]);
		XCTAssertEqualObjects([HyperloopPointer classEncoding], [NSString stringWithUTF8String:@encode(Class)]);
		XCTAssertEqualObjects([HyperloopPointer selectorEncoding], [NSString stringWithUTF8String:@encode(SEL)]);
		XCTAssertEqualObjects([HyperloopPointer unsignedIntEncoding], [NSString stringWithUTF8String:@encode(unsigned int)]);
		XCTAssertEqualObjects([HyperloopPointer unsignedLongEncoding], [NSString stringWithUTF8String:@encode(unsigned long)]);
		XCTAssertEqualObjects([HyperloopPointer unsignedLongLongEncoding], [NSString stringWithUTF8String:@encode(unsigned long long)]);
		XCTAssertEqualObjects([HyperloopPointer unsignedCharEncoding], [NSString stringWithUTF8String:@encode(unsigned char)]);
		XCTAssertEqualObjects([HyperloopPointer floatPointerEncoding], [NSString stringWithUTF8String:@encode(float *)]);
		XCTAssertEqualObjects([HyperloopPointer longPointerEncoding], [NSString stringWithUTF8String:@encode(long *)]);
		XCTAssertEqualObjects([HyperloopPointer intPointerEncoding], [NSString stringWithUTF8String:@encode(int *)]);
		XCTAssertEqualObjects([HyperloopPointer doublePointerEncoding], [NSString stringWithUTF8String:@encode(double *)]);
		XCTAssertEqualObjects([HyperloopPointer shortPointerEncoding], [NSString stringWithUTF8String:@encode(short *)]);
		XCTAssertEqualObjects([HyperloopPointer boolPointerEncoding], [NSString stringWithUTF8String:@encode(bool *)]);
	}
}

- (void)testDispatch {
	@autoreleasepool {
		HyperloopPointer *st = [HyperloopPointer encoding:"{f}"];
		[st setValue:@2 atIndex:0];
		HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(valueAtIndex:) args:@[@0] target:st instance:YES];
		XCTAssertNotNil(result);
		XCTAssertEqual([result floatValue], 2.0f);
	}
}

- (void)testSetNestedStruct {
	@autoreleasepool {
		HyperloopPointer *st = [HyperloopPointer encoding:@encode(CGRect)];
		HyperloopPointer *sp = [HyperloopPointer encoding:@encode(CGPoint)];
		HyperloopPointer *ss = [HyperloopPointer encoding:@encode(CGSize)];
		[sp setValue:@10 atIndex:0];
		[sp setValue:@20 atIndex:1];
		[ss setValue:@100 atIndex:0];
		[ss setValue:@200 atIndex:1];
		[st setValue:[sp valueAtIndex:0] atIndex:0];
		[st setValue:[sp valueAtIndex:1] atIndex:1];
		[st setValue:[ss valueAtIndex:0] atIndex:2];
		[st setValue:[ss valueAtIndex:1] atIndex:3];
		XCTAssertEqual([[st valueAtIndex:0] doubleValue], 10);

		XCTAssertEqual([[st valueAtIndex:1] doubleValue], 20);
		XCTAssertEqual([[st valueAtIndex:2] doubleValue], 100);
		XCTAssertEqual([[st valueAtIndex:3] doubleValue], 200);
		XCTAssertEqual([[sp valueAtIndex:0] doubleValue], 10);
		XCTAssertEqual([[sp valueAtIndex:1] doubleValue], 20);
		XCTAssertEqual([[ss valueAtIndex:0] doubleValue], 100);
		XCTAssertEqual([[ss valueAtIndex:1] doubleValue], 200);
		[ss setValue:@1000 atIndex:0];
		XCTAssertEqual([[ss valueAtIndex:0] doubleValue], 1000);
		XCTAssertEqual([[st valueAtIndex:3] doubleValue], 200);

		UIView *view = [[UIView alloc] init];
		view.frame = *(CGRect *)[st pointerValue];

		XCTAssertEqual(view.frame.size.width, 100);
	}
}

- (void)testCFStringRef {
	@autoreleasepool {
		CFStringRef result = kCGPDFContextUserPassword;
		HyperloopPointer *p = [HyperloopPointer pointer:(const void *)&result encoding:@encode(CFStringRef)];
		CFStringRef v = *(CFStringRef *)[p pointerValue];
		XCTAssertEqual(v, result);
	}
}

- (void)testCharStarPointer {
	@autoreleasepool {
		HyperloopPointer *p = [HyperloopPointer encoding:@encode(char **)];
		char ** value = (char **)[p pointerValue];
		*value = "a";
		NSString *str = [p valueAtIndex:0];
		XCTAssertTrue(strstr(*value, [str UTF8String]) == *value);
	}
}

- (void)testURLStringify {
	@autoreleasepool {
		NSURL *url = [NSURL URLWithString:@"http://www.appcelerator.com"];
		HyperloopPointer *p = [HyperloopPointer pointer:(const void *)url encoding:@encode(id)];
		XCTAssertEqualObjects([url absoluteString], [p stringValue]);
		XCTAssertEqualObjects([url absoluteString], [HyperloopUtils stringify:p]);
		XCTAssertEqualObjects([url description], [p description]);
		XCTAssertEqualObjects([url absoluteString], [p performSelector:@selector(absoluteString)]);

		HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"NSURL" alloc:NO init:@selector(class) args:nil];
		id result = [HyperloopUtils invokeSelector:@selector(URLWithString:) args:@[@"http://www.appcelerator.com"] target:cls instance:NO];
		XCTAssertEqualObjects([url absoluteString], [result absoluteString]);
		XCTAssertEqualObjects([url description], [result description]);
	}
}

- (void)testNSDictionary {
	@autoreleasepool {
		NSDictionary *dictionary = @{
			@"key":@"value"
		};
		HyperloopPointer *p = [HyperloopPointer pointer:(const void *)dictionary encoding:@encode(id)];
		XCTAssertEqualObjects([dictionary description], [p stringValue]);
	}
}

- (void)testCleanup {
	// ensure that our object is being properly cleaned up (dealloc)
	@autoreleasepool {
		TestCleanupObject *t = [TestCleanupObject new];
		HyperloopPointer *p = [HyperloopPointer pointer:(const void *)t encoding:@encode(id)];
		XCTAssertTrue([p isEqual:t]);
		p = nil;
		t = nil;
	}
	XCTAssertEqual(testObjectDealloc, 1);
}

/**
 * The backing storage a pointer wrapper owns, read through the private _storage ivar so tests can
 * observe its lifetime with weak references. nil when the wrapper owns none. Throws (failing the
 * test) when the ivar is absent, so ownership assertions cannot pass vacuously.
 */
static NSMutableData *ownedStorage(HyperloopPointer *p) {
	Ivar ivar = class_getInstanceVariable([HyperloopPointer class], "_storage");
	if (!ivar) {
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"HyperloopPointer has no _storage ivar" userInfo:nil];
	}
	return object_getIvar(p, ivar);
}

// Hyperloop.createPointer('^i') path (+encoding:): the zeroed buffer behind pointerValue must
// stay valid after the autorelease pool around its creation drains (heap-use-after-free under ASan
// when it is not owned by the wrapper).
- (void)testCreatedPointerStorageOutlivesAutoreleasePool {
	__weak NSMutableData *weakStorage = nil;
	HyperloopPointer *p = nil;
	@autoreleasepool {
		p = [HyperloopPointer encoding:@encode(int *)];
	}
	@autoreleasepool {
		int *slot = (int *)[p pointerValue];
		XCTAssertTrue(slot != NULL);
		XCTAssertEqual(*slot, 0);
		*slot = 42;
		XCTAssertEqual([[p valueAtIndex:0] intValue], 42);
		weakStorage = ownedStorage(p);
		XCTAssertNotNil(weakStorage);
		XCTAssertEqual([weakStorage mutableBytes], (void *)slot);
	}
	@autoreleasepool {
		p = nil;
	}
	XCTAssertNil(weakStorage);
}

// pointer:encoding: copies the pointee bytes into wrapper storage (it does not alias the source);
// that copy must survive the pool around the wrapper's creation.
- (void)testCopiedPointerStorageOutlivesAutoreleasePool {
	double source = 1.5;
	__weak NSMutableData *weakStorage = nil;
	HyperloopPointer *p = nil;
	@autoreleasepool {
		p = [HyperloopPointer pointer:&source encoding:@encode(double *)];
	}
	@autoreleasepool {
		double *slot = (double *)[p pointerValue];
		XCTAssertTrue(slot != &source);
		XCTAssertEqual(*slot, 1.5);
		*slot = 2.5;
		XCTAssertEqual([[p valueAtIndex:0] doubleValue], 2.5);
		XCTAssertEqual(source, 1.5);
		weakStorage = ownedStorage(p);
		XCTAssertNotNil(weakStorage);
	}
	@autoreleasepool {
		p = nil;
	}
	XCTAssertNil(weakStorage);
}

// Generated block / custom-class callback arguments of pointer type, e.g. BOOL *stop. The wrapper
// stores a copy of the pointer slot (&arg), and the JS -> native conversion reads the slot back.
// The callback's pool drains while JS may still hold the wrapper; the slot must remain readable for
// the callback scope. The native stack address itself is only valid during the callback.
- (void)testGeneratedPointerArgumentSurvivesAutoreleasePool {
	NSArray *items = @[@1, @2, @3];
	__block NSUInteger visited = 0;
	__block HyperloopPointer *heldArgument = nil;
	[items enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *arg2) {
		visited++;
		@autoreleasepool {
			// emitted by hooks/generate/util.js getObjCReturnResult for a 'pointer' argument
			// (block.js generateBlockWrapper, custom.js) with arg = { type: 'pointer', value: 'BOOL *' }
			id _arg2 = (arg2 == nil) ? (id)[NSNull null] : (id)[HyperloopPointer pointer:(const void *)&arg2 encoding:@encode(BOOL *)];
			heldArgument = _arg2;
		}
		@autoreleasepool {
			// emitted by hooks/generate/util.js generateObjCValue for the same argument (JS -> native)
			BOOL * stop = *(BOOL **)[(HyperloopPointer *)heldArgument pointerValue];
			XCTAssertEqual(stop, arg2);
			*stop = YES;
		}
	}];
	XCTAssertEqual(visited, 1);

	__weak NSMutableData *weakStorage = nil;
	@autoreleasepool {
		weakStorage = ownedStorage(heldArgument);
		XCTAssertNotNil(weakStorage);
		heldArgument = nil;
	}
	XCTAssertNil(weakStorage);
}

// create:encoding: borrows the address: the wrapper owns no storage, reads through the caller's
// memory and never frees it (a double free below would abort if it did).
- (void)testBorrowedPointerIsNotOwned {
	int *borrowed = calloc(2, sizeof(int));
	__weak HyperloopPointer *weakPointer = nil;
	@autoreleasepool {
		HyperloopPointer *p = [HyperloopPointer create:borrowed encoding:@encode(int *)];
		weakPointer = p;
		XCTAssertEqual([p pointerValue], (void *)borrowed);
		XCTAssertNil(ownedStorage(p));
		borrowed[0] = 5;
		XCTAssertEqual([[p valueAtIndex:0] intValue], 5);
	}
	XCTAssertNil(weakPointer);
	borrowed[1] = 9;
	XCTAssertEqual(borrowed[1], 9);
	free(borrowed);
}

// setValue:atIndex: on owned storage writes in place: the address (which also keys the JS wrapper
// table) stays stable, other elements are kept, and the storage is released with the wrapper.
- (void)testSetValueWritesOwnedStorageInPlace {
	__weak NSMutableData *weakStorage = nil;
	HyperloopPointer *p = nil;
	void *address = NULL;
	@autoreleasepool {
		p = [HyperloopPointer encoding:@encode(int *)];
		weakStorage = ownedStorage(p);
		XCTAssertNotNil(weakStorage);
		address = [p pointerValue];
		[p setValue:@7 atIndex:0];
		[p setValue:@8 atIndex:1];
		XCTAssertTrue(ownedStorage(p) == weakStorage);
	}
	@autoreleasepool {
		XCTAssertNotNil(weakStorage);
		XCTAssertEqual([p pointerValue], address);
		XCTAssertEqual(((int *)[p pointerValue])[0], 7);
		XCTAssertEqual(((int *)[p pointerValue])[1], 8);
		XCTAssertEqual([[p valueAtIndex:0] intValue], 7);
		XCTAssertEqual([[p valueAtIndex:1] intValue], 8);
	}
	@autoreleasepool {
		p = nil;
	}
	XCTAssertNil(weakStorage);
}

// value encodings are read through the NSValue copy in _value; an in-place write must refresh it
- (void)testSetValueWritesOwnedValueInPlace {
	@autoreleasepool {
		HyperloopPointer *p = [HyperloopPointer encoding:@encode(int)];
		NSMutableData *storage = ownedStorage(p);
		XCTAssertNotNil(storage);
		void *bytes = [storage mutableBytes];
		[p setValue:@7 atIndex:0];
		XCTAssertTrue(ownedStorage(p) == storage);
		XCTAssertEqual([ownedStorage(p) mutableBytes], bytes);
		XCTAssertEqual(*(int *)bytes, 7);
		XCTAssertEqual([p intValue], 7);
	}
}

// the last element that fits is writable; the first one past the storage, a negative JS index
// (dispatch converts -1 to NSUIntegerMax) and an index whose byte offset wraps around are rejected
// without touching the storage
- (void)testSetValueOwnedStorageBounds {
	@autoreleasepool {
		HyperloopPointer *p = [HyperloopPointer encoding:@encode(int *)];
		NSMutableData *storage = ownedStorage(p);
		int *elements = (int *)[storage mutableBytes];
		NSUInteger count = [storage length] / sizeof(int);
		XCTAssertTrue(count >= 1);
		[p setValue:@7 atIndex:0];
		[p setValue:@9 atIndex:count - 1];
		NSData *before = [storage copy];

		XCTAssertThrowsSpecificNamed([p setValue:@1 atIndex:count], NSException, @"InvalidArgument");
		NSArray *negativeIndexArgs = @[@1, @(-1)];
		XCTAssertThrowsSpecificNamed([HyperloopUtils invokeSelector:@selector(setValue:atIndex:) args:negativeIndexArgs target:p instance:YES], NSException, @"InvalidArgument");
		XCTAssertThrowsSpecificNamed([p setValue:@1 atIndex:NSUIntegerMax / sizeof(int) + 1], NSException, @"InvalidArgument");

		XCTAssertTrue(ownedStorage(p) == storage);
		XCTAssertEqualObjects(storage, before);
		XCTAssertEqual(elements[0], 7);
		XCTAssertEqual(elements[count - 1], 9);
	}
}

// a rejected write leaves the cached scalar value untouched
- (void)testSetValueOutsideOwnedValueKeepsValue {
	@autoreleasepool {
		HyperloopPointer *p = [HyperloopPointer encoding:@encode(int)];
		[p setValue:@5 atIndex:0];
		XCTAssertThrowsSpecificNamed([p setValue:@6 atIndex:1], NSException, @"InvalidArgument");
		XCTAssertEqual([p intValue], 5);
		XCTAssertEqual(*(int *)[ownedStorage(p) mutableBytes], 5);
	}
}

// 'l' is a 4-byte element in ObjC type encodings, but the value is converted as a (64-bit) long;
// the write must not spill into the neighbouring element
- (void)testSetValueRejectsElementWidthMismatch {
	@autoreleasepool {
		HyperloopPointer *p = [HyperloopPointer encoding:"^l"];
		NSMutableData *storage = ownedStorage(p);
		NSData *before = [storage copy];
		XCTAssertThrowsSpecificNamed([p setValue:@1 atIndex:0], NSException, @"InvalidArgument");
		XCTAssertEqualObjects(storage, before);
	}
}

// pointer:encoding: with a pointer encoding copies a pointer slot: the argument is the address of a
// T * (as generated bindings pass &arg), never the T it points to. The copy is sizeof(T *) bytes read
// from the slot, so the pointee (a single 4-byte int here) is not read by the constructor.
- (void)testCopiedPointerEncodingCopiesPointerSlot {
	int *ip = malloc(sizeof(int));
	*ip = 123;
	@autoreleasepool {
		int *slot = ip;
		HyperloopPointer *p = [HyperloopPointer pointer:&slot encoding:@encode(int *)];
		NSMutableData *storage = ownedStorage(p);
		XCTAssertNotNil(storage);
		XCTAssertEqual([storage length], sizeof(int *));
		XCTAssertTrue([p pointerValue] != (void *)&slot);
		// the slot was copied: clearing the source slot does not change the wrapped address
		slot = NULL;
		int *extracted = *(int **)[p pointerValue];
		XCTAssertEqual(extracted, ip);
		XCTAssertEqual(*extracted, 123);
	}
	XCTAssertEqual(*ip, 123);
	free(ip);
}

// the slot copy must not depend on the pointee being pointer-sized: 1, 2 and 8 byte pointees, each in
// an allocation of exactly that size, keep their full native address through the generated pattern
// (pointer:&slot encoding:@encode(T *) then *(T **)pointerValue) and are read in bounds when borrowed
- (void)testPointerSlotAndBorrowAcrossPointeeWidths {
	BOOL *b = malloc(sizeof(BOOL));
	short *s = malloc(sizeof(short));
	double *d = malloc(sizeof(double));
	*b = YES;
	*s = -1234;
	*d = 2.75;
	@autoreleasepool {
		HyperloopPointer *pb = [HyperloopPointer pointer:(const void *)&b encoding:@encode(BOOL *)];
		HyperloopPointer *ps = [HyperloopPointer pointer:(const void *)&s encoding:@encode(short *)];
		HyperloopPointer *pd = [HyperloopPointer pointer:(const void *)&d encoding:@encode(double *)];
		XCTAssertEqual(*(BOOL **)[pb pointerValue], b);
		XCTAssertEqual(*(short **)[ps pointerValue], s);
		XCTAssertEqual(*(double **)[pd pointerValue], d);
		XCTAssertEqual(**(BOOL **)[pb pointerValue], YES);
		XCTAssertEqual(**(short **)[ps pointerValue], -1234);
		XCTAssertEqual(**(double **)[pd pointerValue], 2.75);

		HyperloopPointer *bb = [HyperloopPointer create:b encoding:@encode(BOOL *)];
		HyperloopPointer *bs = [HyperloopPointer create:s encoding:@encode(short *)];
		HyperloopPointer *bd = [HyperloopPointer create:d encoding:@encode(double *)];
		XCTAssertEqual([bb pointerValue], (void *)b);
		XCTAssertEqual([bs pointerValue], (void *)s);
		XCTAssertEqual([bd pointerValue], (void *)d);
		XCTAssertEqual([[bb valueAtIndex:0] boolValue], YES);
		XCTAssertEqual([[bs valueAtIndex:0] shortValue], -1234);
		XCTAssertEqual([[bd valueAtIndex:0] doubleValue], 2.75);
		XCTAssertNil(ownedStorage(bb));
		XCTAssertNil(ownedStorage(bs));
		XCTAssertNil(ownedStorage(bd));
	}
	// borrowed pointees are untouched and still owned (freed) by the caller
	XCTAssertEqual(*b, YES);
	XCTAssertEqual(*s, -1234);
	XCTAssertEqual(*d, 2.75);
	free(b);
	free(s);
	free(d);
}

// ^^i keeps both levels: a slot copy of an int ** yields the int ** back, and a borrowed int ** is the
// native address itself, whose element is the int *
- (void)testPointerToPointerKeepsIndirection {
	int *ip = malloc(sizeof(int));
	*ip = 77;
	int **pp = malloc(sizeof(int *));
	*pp = ip;
	@autoreleasepool {
		HyperloopPointer *slot = [HyperloopPointer pointer:(const void *)&pp encoding:@encode(int **)];
		XCTAssertEqualObjects([slot encoding], @"^^i");
		XCTAssertEqual([ownedStorage(slot) length], sizeof(int **));
		XCTAssertEqual(*(int ***)[slot pointerValue], pp);
		XCTAssertEqual(**(int ***)[slot pointerValue], ip);
		XCTAssertEqual(***(int ***)[slot pointerValue], 77);

		HyperloopPointer *borrowed = [HyperloopPointer create:pp encoding:@encode(int **)];
		XCTAssertEqual([borrowed pointerValue], (void *)pp);
		XCTAssertEqual(*(int **)[borrowed pointerValue], ip);
		XCTAssertNil(ownedStorage(borrowed));
		// element 0 is the int *, carried as a copied pointer slot
		HyperloopPointer *element = [borrowed valueAtIndex:0];
		XCTAssertTrue([element isKindOfClass:[HyperloopPointer class]]);
		XCTAssertEqual(*(int **)[element pointerValue], ip);
	}
	XCTAssertEqual(*pp, ip);
	XCTAssertEqual(*ip, 77);
	free(pp);
	free(ip);
}

// a const-qualified pointer encoding (r^i) is the same pointer slot: the qualifier is stripped from
// the wrapper's encoding and the copy is still sizeof(const int *)
- (void)testQualifiedPointerEncodingCopiesPointerSlot {
	XCTAssertEqual(strcmp(@encode(const int *), "r^i"), 0);
	int *ip = malloc(sizeof(int));
	*ip = 31;
	const int *cip = ip;
	@autoreleasepool {
		HyperloopPointer *p = [HyperloopPointer pointer:(const void *)&cip encoding:@encode(const int *)];
		XCTAssertEqualObjects([p encoding], @"^i");
		XCTAssertEqual([ownedStorage(p) length], sizeof(const int *));
		XCTAssertEqual(*(const int **)[p pointerValue], cip);
		XCTAssertEqual(**(const int **)[p pointerValue], 31);

		HyperloopPointer *b = [HyperloopPointer create:cip encoding:@encode(const int *)];
		XCTAssertEqualObjects([b encoding], @"^i");
		XCTAssertEqual([b pointerValue], (void *)cip);
		XCTAssertEqual([[b valueAtIndex:0] intValue], 31);
	}
	free(ip);
}

// a NULL source keeps its established meanings: pointer:encoding: copies nothing and holds a NULL
// pointer in a zeroed slot it owns; create:encoding: borrows NULL itself
- (void)testNullPointerEncodingSource {
	@autoreleasepool {
		HyperloopPointer *p = [HyperloopPointer pointer:NULL encoding:@encode(int *)];
		XCTAssertEqual([ownedStorage(p) length], sizeof(int *));
		XCTAssertTrue([p pointerValue] != NULL);
		XCTAssertTrue(*(int **)[p pointerValue] == NULL);

		HyperloopPointer *b = [HyperloopPointer create:NULL encoding:@encode(int *)];
		XCTAssertTrue([b pointerValue] == NULL);
		XCTAssertNil(ownedStorage(b));
	}
}

#pragma mark - typed numeric accessors

// typed accessors convert the stored value into the requested type instead of copying the stored bytes
- (void)testDoubleConvertsToInt {
	@autoreleasepool {
		double d = 3.0;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] intValue], 3);
		d = 2.75;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] intValue], 2);
		d = -2.75;
		HyperloopPointer *p = [HyperloopPointer pointer:&d encoding:@encode(double)];
		XCTAssertEqual([p intValue], -2);
		XCTAssertEqual([p shortValue], -2);
		XCTAssertEqual([p charValue], -2);
		XCTAssertEqual([p longLongValue], -2);
		XCTAssertEqual([HyperloopPointer intValue:p], -2);
	}
}

- (void)testSmallIntegerWidensToWiderType {
	@autoreleasepool {
		signed char c = -5;
		HyperloopPointer *p = [HyperloopPointer pointer:&c encoding:@encode(signed char)];
		XCTAssertEqual([p intValue], -5);
		XCTAssertEqual([p longLongValue], -5);
		XCTAssertEqual([p doubleValue], -5.0);

		short s = -1;
		p = [HyperloopPointer pointer:&s encoding:@encode(short)];
		XCTAssertEqual([p intValue], -1);
		XCTAssertEqual([p longValue], -1);

		unsigned char uc = 200;
		p = [HyperloopPointer pointer:&uc encoding:@encode(unsigned char)];
		XCTAssertEqual([p intValue], 200);
		XCTAssertEqual([p longLongValue], 200);

		unsigned int ui = 4000000000u;
		p = [HyperloopPointer pointer:&ui encoding:@encode(unsigned int)];
		XCTAssertEqual([p longLongValue], 4000000000LL);
		XCTAssertEqual([p unsignedLongLongValue], 4000000000ULL);
		XCTAssertEqual([p doubleValue], 4000000000.0);
	}
}

// explicit 'l'/'L' encodings are 4 bytes, unlike the 8 byte C long they are named after
- (void)testFourByteLongEncodingConvertsToLong {
	@autoreleasepool {
		NSUInteger size = 0;
		NSGetSizeAndAlignment("l", &size, NULL);
		XCTAssertEqual(size, sizeof(int32_t));

		int32_t l = -7;
		HyperloopPointer *p = [HyperloopPointer pointer:&l encoding:"l"];
		XCTAssertEqual([p longValue], -7L);
		XCTAssertEqual([p intValue], -7);

		uint32_t ul = UINT32_MAX;
		p = [HyperloopPointer pointer:&ul encoding:"L"];
		XCTAssertEqual([p unsignedLongValue], (unsigned long)UINT32_MAX);
		XCTAssertEqual([p longLongValue], (long long)UINT32_MAX);
	}
}

- (void)testIntegerConvertsToFloatingPoint {
	@autoreleasepool {
		int i = 7;
		HyperloopPointer *p = [HyperloopPointer pointer:&i encoding:@encode(int)];
		XCTAssertEqual([p doubleValue], 7.0);
		XCTAssertEqual([p floatValue], 7.0f);

		i = -3;
		p = [HyperloopPointer pointer:&i encoding:@encode(int)];
		XCTAssertEqual([p doubleValue], -3.0);

		float f = 1.1f;
		p = [HyperloopPointer pointer:&f encoding:@encode(float)];
		// float widens to double exactly; it does not round to the nearest double of 1.1
		XCTAssertEqual([p doubleValue], (double)1.1f);
		XCTAssertEqualWithAccuracy([p doubleValue], 1.1, 1e-6);

		double d = 0.1;
		p = [HyperloopPointer pointer:&d encoding:@encode(double)];
		XCTAssertEqual([p floatValue], 0.1f);
	}
}

// 64-bit integers keep their value above 2^53 instead of being rounded through a double
- (void)testSixtyFourBitIntegersArePreserved {
	@autoreleasepool {
		long long ll = (1LL << 53) + 1;
		HyperloopPointer *p = [HyperloopPointer pointer:&ll encoding:@encode(long long)];
		XCTAssertEqual([p longLongValue], ll);
		XCTAssertEqual([p longValue], (long)ll);
		XCTAssertEqual([p unsignedLongLongValue], (unsigned long long)ll);

		unsigned long long ull = (1ULL << 63) + 5;
		p = [HyperloopPointer pointer:&ull encoding:@encode(unsigned long long)];
		XCTAssertEqual([p unsignedLongLongValue], ull);
		XCTAssertEqual([p unsignedLongValue], (unsigned long)ull);
		XCTAssertEqual([p doubleValue], 9223372036854775808.0);

		ll = -1;
		p = [HyperloopPointer pointer:&ll encoding:@encode(long long)];
		XCTAssertEqual([p unsignedLongLongValue], ULLONG_MAX);
	}
}

// integer narrowing keeps the low-order bits, as a C conversion does
- (void)testIntegerNarrowingWraps {
	@autoreleasepool {
		int i = 0x12345;
		HyperloopPointer *p = [HyperloopPointer pointer:&i encoding:@encode(int)];
		XCTAssertEqual([p shortValue], (short)0x2345);
		XCTAssertEqual([p unsignedCharValue], 0x45);

		long long ll = -1;
		p = [HyperloopPointer pointer:&ll encoding:@encode(long long)];
		XCTAssertEqual([p unsignedIntValue], UINT_MAX);
		XCTAssertEqual([p intValue], -1);
	}
}

- (void)testBoolConversions {
	@autoreleasepool {
		double d = 0.0;
		XCTAssertFalse([[HyperloopPointer pointer:&d encoding:@encode(double)] boolValue]);
		d = 0.25;
		XCTAssertTrue([[HyperloopPointer pointer:&d encoding:@encode(double)] boolValue]);
		d = -1.0;
		XCTAssertTrue([[HyperloopPointer pointer:&d encoding:@encode(double)] boolValue]);

		int i = 0;
		XCTAssertFalse([[HyperloopPointer pointer:&i encoding:@encode(int)] boolValue]);
		i = 256;
		XCTAssertTrue([[HyperloopPointer pointer:&i encoding:@encode(int)] boolValue]);

		bool b = true;
		HyperloopPointer *p = [HyperloopPointer pointer:&b encoding:@encode(bool)];
		XCTAssertEqual([p doubleValue], 1.0);
		XCTAssertEqual([p longLongValue], 1);
	}
}

// floating values truncate toward zero; NaN converts to 0 and values beyond the destination range
// saturate to its limits, where a C conversion would be undefined
- (void)testFloatingToIntegerBoundaries {
	@autoreleasepool {
		double d = 1e20;
		HyperloopPointer *p = [HyperloopPointer pointer:&d encoding:@encode(double)];
		XCTAssertEqual([p intValue], INT_MAX);
		XCTAssertEqual([p longLongValue], LLONG_MAX);
		XCTAssertEqual([p unsignedLongLongValue], ULLONG_MAX);
		XCTAssertEqual([p charValue], CHAR_MAX);

		d = -1e20;
		p = [HyperloopPointer pointer:&d encoding:@encode(double)];
		XCTAssertEqual([p intValue], INT_MIN);
		XCTAssertEqual([p longLongValue], LLONG_MIN);
		XCTAssertEqual([p unsignedIntValue], 0u);

		d = 2147483648.0;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] intValue], INT_MAX);
		d = -2147483648.0;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] intValue], INT_MIN);
		d = 9223372036854775808.0;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] longLongValue], LLONG_MAX);
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] unsignedLongLongValue], 9223372036854775808ULL);

		d = -0.5;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] unsignedIntValue], 0u);
		d = -1.0;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] unsignedIntValue], 0u);

		d = INFINITY;
		p = [HyperloopPointer pointer:&d encoding:@encode(double)];
		XCTAssertEqual([p intValue], INT_MAX);
		XCTAssertTrue([p boolValue]);
		XCTAssertEqual([p floatValue], INFINITY);
		d = -INFINITY;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] intValue], INT_MIN);

		d = NAN;
		p = [HyperloopPointer pointer:&d encoding:@encode(double)];
		XCTAssertEqual([p intValue], 0);
		XCTAssertEqual([p unsignedLongLongValue], 0ull);
		XCTAssertTrue([p boolValue]);
		XCTAssertTrue(isnan([p floatValue]));

		float f = 3e9f;
		XCTAssertEqual([[HyperloopPointer pointer:&f encoding:@encode(float)] intValue], INT_MAX);
		XCTAssertEqual([[HyperloopPointer pointer:&f encoding:@encode(float)] unsignedIntValue], 3000000000u);
	}
}

// finite doubles beyond the float range become the infinity of their sign; everything else converts as is
- (void)testDoubleToFloatOverflow {
	@autoreleasepool {
		double d = FLT_MAX;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] floatValue], FLT_MAX);
		d = -FLT_MAX;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] floatValue], -FLT_MAX);
		d = nextafter((double)FLT_MAX, INFINITY);
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] floatValue], INFINITY);
		d = nextafter(-(double)FLT_MAX, -INFINITY);
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] floatValue], -INFINITY);
		d = 1e300;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] floatValue], INFINITY);
		d = -1e300;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] floatValue], -INFINITY);

		d = INFINITY;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] floatValue], INFINITY);
		d = -INFINITY;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] floatValue], -INFINITY);
		d = NAN;
		XCTAssertTrue(isnan([[HyperloopPointer pointer:&d encoding:@encode(double)] floatValue]));

		d = 0.0;
		float zero = [[HyperloopPointer pointer:&d encoding:@encode(double)] floatValue];
		XCTAssertEqual(zero, 0.0f);
		XCTAssertFalse(signbit(zero));
		d = -0.0;
		float negativeZero = [[HyperloopPointer pointer:&d encoding:@encode(double)] floatValue];
		XCTAssertEqual(negativeZero, 0.0f);
		XCTAssertTrue(signbit(negativeZero));

		d = -2.5;
		XCTAssertEqual([[HyperloopPointer pointer:&d encoding:@encode(double)] floatValue], -2.5f);
	}
}

static HyperloopPointer *doublePointer(double d) {
	return [HyperloopPointer pointer:&d encoding:@encode(double)];
}

static HyperloopPointer *floatPointer(float f) {
	return [HyperloopPointer pointer:&f encoding:@encode(float)];
}

// exact conversion limits and their neighbouring representable values: (double)LLONG_MAX and
// (double)ULLONG_MAX round up to 2^63 and 2^64, which are themselves out of range
- (void)testFloatingToIntegerExactLimits {
	@autoreleasepool {
		XCTAssertEqual([doublePointer(0x1p63) longLongValue], LLONG_MAX);
		XCTAssertEqual([doublePointer(nextafter(0x1p63, 0)) longLongValue], 9223372036854774784LL);
		XCTAssertEqual([doublePointer(-0x1p63) longLongValue], LLONG_MIN);
		XCTAssertEqual([doublePointer(nextafter(-0x1p63, 0)) longLongValue], -9223372036854774784LL);
		XCTAssertEqual([doublePointer(nextafter(-0x1p63, -INFINITY)) longLongValue], LLONG_MIN);

		XCTAssertEqual([doublePointer(0x1p64) unsignedLongLongValue], ULLONG_MAX);
		XCTAssertEqual([doublePointer(nextafter(0x1p64, 0)) unsignedLongLongValue], 18446744073709549568ULL);
		XCTAssertEqual([doublePointer(nextafter(0x1p64, INFINITY)) unsignedLongLongValue], ULLONG_MAX);
		XCTAssertEqual([doublePointer(0x1p63) unsignedLongLongValue], 9223372036854775808ULL);

		XCTAssertEqual([doublePointer(2147483647.0) intValue], INT_MAX);
		XCTAssertEqual([doublePointer(nextafter(2147483647.0, 0)) intValue], 2147483646);
		XCTAssertEqual([doublePointer(2147483647.75) intValue], INT_MAX);
		XCTAssertEqual([doublePointer(nextafter(0x1p31, INFINITY)) intValue], INT_MAX);
		XCTAssertEqual([doublePointer(-2147483648.0) intValue], INT_MIN);
		XCTAssertEqual([doublePointer(nextafter(-2147483648.0, 0)) intValue], -2147483647);
		XCTAssertEqual([doublePointer(-2147483648.75) intValue], INT_MIN);
		XCTAssertEqual([doublePointer(-2147483649.0) intValue], INT_MIN);

		XCTAssertEqual([doublePointer(4294967295.0) unsignedIntValue], UINT_MAX);
		XCTAssertEqual([doublePointer(nextafter(0x1p32, 0)) unsignedIntValue], UINT_MAX);
		XCTAssertEqual([doublePointer(0x1p32) unsignedIntValue], UINT_MAX);
		XCTAssertEqual([doublePointer(-0.0) unsignedIntValue], 0u);
		XCTAssertEqual([doublePointer(nextafter(0.0, -1.0)) unsignedIntValue], 0u);
		XCTAssertEqual([doublePointer(-0.75) unsignedLongLongValue], 0ull);
		XCTAssertEqual([doublePointer(-INFINITY) unsignedLongLongValue], 0ull);
		XCTAssertEqual([doublePointer(INFINITY) unsignedLongLongValue], ULLONG_MAX);
		XCTAssertEqual([doublePointer(INFINITY) longLongValue], LLONG_MAX);
		XCTAssertEqual([doublePointer(-INFINITY) longLongValue], LLONG_MIN);

		// float sources widen to double exactly before the same checks
		XCTAssertEqual([floatPointer(nextafterf(0x1p31f, 0)) intValue], 2147483520);
		XCTAssertEqual([floatPointer(0x1p31f) intValue], INT_MAX);
		XCTAssertEqual([floatPointer(nextafterf(0x1p63f, 0)) longLongValue], 9223371487098961920LL);
		XCTAssertEqual([floatPointer(0x1p63f) longLongValue], LLONG_MAX);
		XCTAssertEqual([floatPointer(-0x1p63f) longLongValue], LLONG_MIN);
		XCTAssertEqual([floatPointer(nextafterf(0x1p64f, 0)) unsignedLongLongValue], 18446742974197923840ULL);
		XCTAssertEqual([floatPointer(0x1p64f) unsignedLongLongValue], ULLONG_MAX);
		XCTAssertEqual([floatPointer(-1.0f) unsignedLongLongValue], 0ull);
		XCTAssertEqual([floatPointer(NAN) longLongValue], 0LL);
		XCTAssertEqual([floatPointer(-INFINITY) intValue], INT_MIN);
	}
}

// signed and unsigned crossings: unsigned destinations reduce modulo 2^N; out-of-range signed
// destinations rely on Clang reducing modulo 2^N as well
- (void)testIntegerSignednessCrossings {
	@autoreleasepool {
		int i = -1;
		HyperloopPointer *p = [HyperloopPointer pointer:&i encoding:@encode(int)];
		XCTAssertEqual([p unsignedShortValue], USHRT_MAX);
		XCTAssertEqual([p unsignedLongLongValue], ULLONG_MAX);

		short s = -2;
		p = [HyperloopPointer pointer:&s encoding:@encode(short)];
		XCTAssertEqual([p unsignedIntValue], UINT_MAX - 1);

		unsigned short us = USHRT_MAX;
		p = [HyperloopPointer pointer:&us encoding:@encode(unsigned short)];
		XCTAssertEqual([p intValue], 65535);

		unsigned int ui = UINT_MAX;
		p = [HyperloopPointer pointer:&ui encoding:@encode(unsigned int)];
		XCTAssertEqual([p intValue], -1);

		i = 0x18000;
		p = [HyperloopPointer pointer:&i encoding:@encode(int)];
		XCTAssertEqual([p shortValue], SHRT_MIN);

		unsigned long long ull = (1ULL << 63) + 5;
		p = [HyperloopPointer pointer:&ull encoding:@encode(unsigned long long)];
		XCTAssertEqual([p longLongValue], LLONG_MIN + 5);
	}
}

// an object-backed NSNumber converts like the scalar it holds; other objects have no numeric value
- (void)testObjectBackedNumberConverts {
	@autoreleasepool {
		HyperloopPointer *p = [HyperloopPointer pointer:(__bridge void *)@42 encoding:@encode(id)];
		XCTAssertEqual([p intValue], 42);
		XCTAssertEqual([p doubleValue], 42.0);

		p = [HyperloopPointer pointer:(__bridge void *)@2.5 encoding:@encode(id)];
		XCTAssertEqual([p intValue], 2);
		XCTAssertEqual([p doubleValue], 2.5);

		p = [HyperloopPointer pointer:(__bridge void *)@(LLONG_MAX) encoding:@encode(id)];
		XCTAssertEqual([p longLongValue], LLONG_MAX);

		p = [HyperloopPointer pointer:(__bridge void *)@YES encoding:@encode(id)];
		XCTAssertTrue([p boolValue]);
		XCTAssertEqual([p intValue], 1);

		p = [HyperloopPointer pointer:(__bridge void *)[NSValue valueWithCGPoint:CGPointMake(3, 4)] encoding:@encode(id)];
		XCTAssertEqual([p intValue], 0);

		p = [HyperloopPointer pointer:(__bridge void *)@"42" encoding:@encode(id)];
		XCTAssertEqual([p intValue], 0);
	}
}

// type qualifiers left on the stored encoding do not change how the value is decoded
- (void)testQualifiedEncodingConverts {
	@autoreleasepool {
		int i = -9;
		HyperloopPointer *p = [HyperloopPointer pointer:&i encoding:"rni"];
		XCTAssertEqual([p intValue], -9);
		XCTAssertEqual([p longLongValue], -9);
		XCTAssertEqual([p doubleValue], -9.0);
	}
}

// storage that is not a numeric scalar has no numeric value; the accessors return their default
// rather than copying its bytes into the result
- (void)testNonNumericStorageReturnsDefault {
	@autoreleasepool {
		HyperloopPointer *p = [HyperloopPointer create:NULL encoding:"^i"];
		XCTAssertEqual([p intValue], 0);
		XCTAssertEqual([p doubleValue], 0.0);

		const char *str = "a string longer than eight bytes";
		p = [HyperloopPointer pointer:str encoding:@encode(char *)];
		XCTAssertEqual([p intValue], 0);
		XCTAssertEqual([p longLongValue], 0);
		XCTAssertEqualObjects([p stringValue], @"a string longer than eight bytes");

		SEL sel = @selector(description);
		p = [HyperloopPointer pointer:sel encoding:@encode(SEL)];
		XCTAssertEqual([p intValue], 0);
		XCTAssertEqualObjects([p selectorValue], @"description");

		CGPoint pt = CGPointMake(1, 2);
		p = [HyperloopPointer pointer:&pt encoding:@encode(CGPoint)];
		XCTAssertEqual([p intValue], 0);
	}
}

// a numeric HyperloopPointer assigned into another pointer's element is converted to the element type
- (void)testSetValueConvertsPointerValueToElementType {
	@autoreleasepool {
		double d = 4.5;
		HyperloopPointer *source = [HyperloopPointer pointer:&d encoding:@encode(double)];
		HyperloopPointer *p = [HyperloopPointer encoding:@encode(int)];
		[p setValue:source atIndex:0];
		XCTAssertEqual([p intValue], 4);
		XCTAssertEqual(*(int *)[ownedStorage(p) mutableBytes], 4);
	}
}

// raw extraction still copies the stored bytes in their own encoding, and only those bytes
- (void)testRawValueExtractionKeepsStoredEncoding {
	@autoreleasepool {
		double d = -2.75;
		HyperloopPointer *p = [HyperloopPointer pointer:&d encoding:@encode(double)];
		double raw = 0;
		[[p value] getValue:&raw];
		XCTAssertEqual(memcmp(&raw, &d, sizeof(d)), 0);
		double element = 0;
		[p getValue:0 pointer:&element];
		XCTAssertEqual(element, d);

		int32_t l = -7;
		p = [HyperloopPointer pointer:&l encoding:"l"];
		XCTAssertEqual([p length], sizeof(int32_t));
		struct { int32_t value; uint8_t canary[4]; } dest = { 0, { 0xA5, 0xA5, 0xA5, 0xA5 } };
		[[p value] getValue:&dest.value];
		XCTAssertEqual(dest.value, -7);
		for (int i = 0; i < 4; i++) {
			XCTAssertEqual(dest.canary[i], 0xA5);
		}
	}
}

@end

#pragma clang diagnostic pop
