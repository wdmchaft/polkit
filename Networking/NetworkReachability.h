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
#import <sys/socket.h>

@class NetworkReachability;

@protocol NetworkReachabilityDelegate <NSObject>
- (void) networkReachabilityDidChange:(NetworkReachability*)reachability;
@end

@interface NetworkReachability : NSObject
{
@private
	void*								_reachability;
	CFRunLoopRef						_runLoop;
	id<NetworkReachabilityDelegate>		_delegate;
}
- (id) init; //Use default route
- (id) initWithAddress:(const struct sockaddr*)address;
- (id) initWithIPv4Address:(UInt32)address; //The "address" is assumed to be in host-endian
- (id) initWithHostName:(NSString*)name;

@property(nonatomic, assign) id<NetworkReachabilityDelegate> delegate;

@property(nonatomic, readonly, getter=isReachable) BOOL reachable;
@end
