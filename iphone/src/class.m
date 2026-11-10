/**
 * Hyperloop iOS-Core
 * Copyright (c) 2015-present by Appcelerator, Inc.
 */
#import <objc/runtime.h>
#import <objc/message.h>
#import "define.h"
#import "class.h"
#import "utils.h"
#import "pointer.h"

/**
 * Whether sel is in the init method family as ARC defines it: after leading
 * underscores, the name starts with "init" not followed by a lowercase letter.
 */
static BOOL IsInitFamilySelector(SEL sel) {
	const char *name = sel_getName(sel);
	while (*name == '_') {
		name++;
	}
	return strncmp(name, "init", 4) == 0 && !islower((unsigned char)name[4]);
}

@implementation HyperloopClass

@synthesize nativeObject = _nativeObject;

- (NSString *)description
{
	if (![self.className isKindOfClass:[NSString class]]) {
		return NSStringFromClass(self.class);
	}
	// Return the object description like in native iOS, e.g. <NSMutableArray: 0x608000072c80>
	return [NSString stringWithFormat:@"<%@: %p>", self.className, self];
}

-(instancetype)initWithClassName: (NSString *)className alloc:(BOOL)alloc init:(SEL)init args:(NSArray*)args {
	if (self = [self init]) {
		Class c = NSClassFromString(className);
		if (c == nil) {
			@throw [NSException exceptionWithName:@"ClassNotFound" reason:[NSString stringWithFormat:@"Cannot find class with name: %@", className] userInfo:nil];
		}
		id nativeObject = nil;
		if (alloc && IsInitFamilySelector(init)) {
			// alloc returns +1. An init-family method consumes that reference and returns
			// its result (self, nil or a replacement) at +1, but NSInvocation calls it as an
			// ordinary method, so ARC performs neither transfer. Hand the allocation's
			// reference to the initializer instead of releasing it again here, and drop the
			// returned reference once the result wrapper has retained the object.
			void *allocated = (__bridge_retained void *)[c alloc];
			nativeObject = [HyperloopUtils invokeSelector:init args:args target:(__bridge id)allocated instance:YES];
			CFBridgingRelease((__bridge CFTypeRef)[nativeObject objectValue]);
		} else {
			id instance = nil;
			BOOL isInstance = YES;
			if (alloc) {
				instance = [c alloc];
			} else {
				instance = c;
				isInstance = NO;
			}
			nativeObject = [HyperloopUtils invokeSelector:init args:args target:instance instance:isInstance];
		}
		id target = [nativeObject objectValue];
		if (!target) {
			target = [nativeObject classValue];
		}
		self.nativeObject = target;
		self.className = className;
	}
	REMEMBER(self);
	return self;
}

-(void)dealloc {
	[self destroy:nil];
	FORGET(self);
}

-(void)destroy:(id)args {
	RELEASE_AND_CHECK(self.nativeObject);
	RELEASE_AND_CHECK(self.customClass);
	RELEASE_AND_CHECK(self.className);
}

-(id)target {
	return self.nativeObject;
}

@end
