/**
 * Hyperloop iOS-Core
 * Copyright (c) 2015-present by Appcelerator, Inc.
 */

import Foundation
import UIKit


open class TestView : UIView {
	
	@objc open func foo (_ x : CGFloat, y : CGFloat) -> CGFloat {
		return x + y;
	}
}
