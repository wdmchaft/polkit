/*
	This file is part of the PolKit library.
	Copyright (C) 2008-2009 Pierre-Olivier Latour <info@pol-online.net>
	
	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.
	
	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.
	
	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <Foundation/Foundation.h>

#define kHIDPathSeparator		@":"

@class HIDController;

@protocol HIDControllerDelegate <NSObject>
- (void) HIDControllerDidConnect:(HIDController*)controller;
- (void) HIDControllerDidDisconnect:(HIDController*)controller;
- (void) HIDController:(HIDController*)controller didUpdateElementWithCookie:(unsigned long)cookie value:(SInt32)value min:(SInt32)min max:(SInt32)max info:(NSDictionary*)info;
@end

@interface HIDController : NSObject
{
@private
	unsigned short				_vendorID,
								_productID,
								_primaryUsagePage,
								_primaryUsage;
	BOOL						_exclusive;
	id<HIDControllerDelegate>	_delegate;
	void*						_hidDeviceInterface;
	void*						_queueInterface;
	CFRunLoopSourceRef			_hidEventSource;
	NSMutableDictionary*		_info;
	CFMutableDictionaryRef		_cookies;
}
+ (BOOL) useDelegateThread; //NO by default
+ (NSDictionary*) allDevices;

- (id) initWithDevicePath:(NSString*)path exclusive:(BOOL)exclusive;
- (id) initWithVendorID:(unsigned short)vendorID productID:(unsigned short)productID primaryUsagePage:(unsigned short)primaryUsagePage primaryUsage:(unsigned short)primaryUsage exclusive:(BOOL)exclusive;
- (unsigned short) vendorID;
- (unsigned short) productID;
- (unsigned short) primaryUsagePage;
- (unsigned short) primaryUsage;
- (BOOL) isExclusive;
- (NSString*) devicePath;

- (void) setDelegate:(id<HIDControllerDelegate>)delegate;
- (id<HIDControllerDelegate>) delegate;

- (BOOL) isConnected;

/* Valid only when connected */
- (NSDictionary*) info;
- (NSDictionary*) allElements;
- (BOOL) fetchElementWithCookie:(unsigned long)cookie value:(SInt32*)value min:(SInt32*)min max:(SInt32*)max;
@end
