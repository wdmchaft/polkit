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

@class NetworkConfiguration;

@protocol NetworkConfigurationDelegate <NSObject>
- (void) networkConfigurationDidChange:(NetworkConfiguration*)configuration;
@end

@interface NetworkConfiguration : NSObject
{
@private
	void*								_dynamicStore;
	id<NetworkConfigurationDelegate>	_delegate;
	CFRunLoopSourceRef					_runLoopSource;
}
+ (NetworkConfiguration*) sharedNetworkConfiguration;

@property(nonatomic, readonly) NSString* locationName;
@property(nonatomic, readonly) NSString* dnsDomainName;
@property(nonatomic, readonly) NSArray* dnsServerAddresses;
@property(nonatomic, readonly) NSArray* networkAddresses;
@property(nonatomic, readonly) NSString* airportNetworkName;
@property(nonatomic, readonly) NSData* airportNetworkSSID;

@property(nonatomic, assign) id<NetworkConfigurationDelegate> delegate;
@end
