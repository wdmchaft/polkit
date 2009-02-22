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

#import <SystemConfiguration/SystemConfiguration.h>

#import "NetworkConfiguration.h"

@implementation NetworkConfiguration

@synthesize delegate=_delegate;

static void _DynamicStoreCallBack(SCDynamicStoreRef store, CFArrayRef changedKeys, void* info)
{
	NSAutoreleasePool*					localPool = [NSAutoreleasePool new];
	
	[((NetworkConfiguration*)info)->_delegate networkConfigurationDidChange:info];
	
	[localPool release];
}

+ (NetworkConfiguration*) sharedNetworkConfiguration
{
	static NetworkConfiguration*		networkConfiguration = nil;
	
	if(networkConfiguration == nil)
	networkConfiguration = [NetworkConfiguration new];
	
	return networkConfiguration;
}

- (id) init
{
	SCDynamicStoreContext				context = {0, self, NULL, NULL, NULL};
	
	if((self = [super init])) {
		_dynamicStore = (void*)SCDynamicStoreCreate(kCFAllocatorDefault, CFSTR("net.pol-online.polkit"), _DynamicStoreCallBack, &context);
		if(_dynamicStore == NULL) {
			NSLog(@"%s: SCDynamicStoreCreate() failed with error \"%s\"", __FUNCTION__, SCErrorString(SCError()));
			[self release];
			return nil;
		}
	}
	
	return self;
}

- (void) dealloc
{
	[self setDelegate:nil];
	
	if(_dynamicStore)
	CFRelease(_dynamicStore);
	
	[super dealloc];
}

- (void) setDelegate:(id<NetworkConfigurationDelegate>)delegate
{
	if(delegate != _delegate) {
		_delegate = delegate;
		
		if(_delegate && !_runLoopSource) {
			if(SCDynamicStoreSetNotificationKeys(_dynamicStore, NULL, (CFArrayRef)[NSArray arrayWithObject:@".*/Network/.*"])) {
				_runLoopSource = SCDynamicStoreCreateRunLoopSource(kCFAllocatorDefault, _dynamicStore, 0);
				if(_runLoopSource)
				CFRunLoopAddSource(CFRunLoopGetCurrent(), _runLoopSource, kCFRunLoopCommonModes);
				else
				NSLog(@"%s: SCDynamicStoreCreateRunLoopSource() failed with error \"%s\"", __FUNCTION__, SCErrorString(SCError()));
			}
			else
			NSLog(@"%s: SCDynamicStoreSetNotificationKeys() failed with error \"%s\"", __FUNCTION__, SCErrorString(SCError()));
		}
		else if(!_delegate && _runLoopSource) {
			CFRunLoopRemoveSource(CFRunLoopGetCurrent(), _runLoopSource, kCFRunLoopCommonModes);
			CFRelease(_runLoopSource);
			_runLoopSource = NULL;
			SCDynamicStoreSetNotificationKeys(_dynamicStore, NULL, NULL);
		}
	}
}

- (NSString*) locationName
{
	return [[(id)SCDynamicStoreCopyValue(_dynamicStore, CFSTR("Setup:/")) autorelease] objectForKey:(id)kSCPropUserDefinedName];
}

- (NSString*) dnsDomainName
{
	return [[(id)SCDynamicStoreCopyValue(_dynamicStore, CFSTR("State:/Network/Global/DNS")) autorelease] objectForKey:(id)kSCPropNetDNSDomainName];
}

- (NSArray*) dnsServerAddresses
{
	return [[(id)SCDynamicStoreCopyValue(_dynamicStore, CFSTR("State:/Network/Global/DNS")) autorelease] objectForKey:(id)kSCPropNetDNSServerAddresses];
}

- (NSArray*) networkAddresses
{
	NSArray*						list = [(id)SCDynamicStoreCopyKeyList(_dynamicStore, CFSTR("State:/Network/Service/.*/IPv4")) autorelease];
	NSMutableArray*					array = [NSMutableArray array];
	NSString*						key;
	
	for(key in list)
	[array addObjectsFromArray:[[(id)SCDynamicStoreCopyValue(_dynamicStore, (CFStringRef)key) autorelease] objectForKey:(id)kSCPropNetIPv4Addresses]];
	
	return array;
}

- (NSDictionary*) _airportInfo
{
	NSArray*						list = [(id)SCDynamicStoreCopyKeyList(_dynamicStore, CFSTR("State:/Network/Interface/.*/AirPort")) autorelease];
	
	return ([list count] ? [(id)SCDynamicStoreCopyValue(_dynamicStore, (CFStringRef)[list objectAtIndex:0]) autorelease] : nil);
}

- (NSString*) airportNetworkName
{
	return [[self _airportInfo] objectForKey:@"SSID_STR"];
}

- (NSData*) airportNetworkSSID
{
	return [[self _airportInfo] objectForKey:@"BSSID"];
}

- (NSString*) description
{
	NSArray*						list = [(id)SCDynamicStoreCopyKeyList(_dynamicStore, CFSTR(".*/Network/.*")) autorelease];
	NSMutableDictionary*			dictionary = [NSMutableDictionary dictionary];
	NSString*						key;
	
	for(key in list)
	[dictionary setValue:[(id)SCDynamicStoreCopyValue(_dynamicStore, (CFStringRef)key) autorelease] forKey:key];
	
	return [dictionary description];
}

@end
