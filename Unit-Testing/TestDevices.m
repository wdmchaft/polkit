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

#import <SenTestingKit/SenTestingKit.h>
#import <IOKit/hid/IOHIDUsageTables.h>
#import <IOKit/hid/IOHIDKeys.h>

#import "HIDController.h"
#import "MidiController.h"

@interface DevicesTestCase : SenTestCase
@end

@implementation DevicesTestCase

- (void) testHID
{
	HIDController*			controller = nil;
	NSDictionary*			dictionary;
	NSString*				key;
	
	dictionary = [HIDController allDevices];
	STAssertNotNil(dictionary, nil);
	
	for(key in dictionary) {
		if(([[[dictionary objectForKey:key] objectForKey:@"Product"] rangeOfString:@"Keyboard"].location != NSNotFound) && ([[[dictionary objectForKey:key] objectForKey:@kIOHIDPrimaryUsageKey] unsignedShortValue] == kHIDUsage_GD_Keyboard)) {
			controller = [[HIDController alloc] initWithDevicePath:key exclusive:NO];
			STAssertNotNil(controller, nil);
			STAssertTrue([controller vendorID], nil);
			STAssertTrue([controller productID], nil);
			STAssertTrue([controller primaryUsagePage], nil);
			STAssertTrue([controller primaryUsage], nil);
			STAssertNotNil([controller devicePath], nil);
			STAssertTrue([controller isConnected], nil);
			STAssertNotNil([controller info], nil);
			STAssertNotNil([controller allElements], nil);
			[controller release];
			return;
		}
	}
	
	STAssertNotNil(controller, nil);
}

- (void) testMidi
{
	MidiController*			controller;
	
	controller = [[MidiController alloc] initWithName:@"PolKit" uniqueID:0];
	STAssertNotNil(controller, nil);
	[controller release];
}

@end
