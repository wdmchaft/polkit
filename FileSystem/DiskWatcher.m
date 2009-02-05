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

#import <DiskArbitration/DiskArbitration.h>
#import <sys/mount.h>

#import "DiskWatcher.h"

@implementation DiskWatcher

@synthesize diskUUID=_uuid, delegate=_delegate;

static CFUUIDRef _CreateDiskUUIDFromVolumeName(DASessionRef session, NSString* name)
{
	CFUUIDRef				uuid = NULL;
	DADiskRef				disk;
	CFDictionaryRef			description;
	struct statfs			stats;
	
	if(statfs([[@"/Volumes" stringByAppendingPathComponent:name] UTF8String], &stats) != 0)
	return NULL;
	
	disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, stats.f_mntfromname);
	if(disk) {
		description = DADiskCopyDescription(disk);
		if(description) {
			if((uuid = CFDictionaryGetValue(description, kDADiskDescriptionVolumeUUIDKey)))
			CFRetain(uuid);
			CFRelease(description);
		}
		CFRelease(disk);
	}
	
	return uuid;
}

+ (NSString*) diskUUIDForVolumeName:(NSString*)name
{
	NSString*				string = nil;
	DASessionRef			session;
	CFUUIDRef				uuid;
	
	session = DASessionCreate(kCFAllocatorDefault);
	if(session) {
		if((uuid = _CreateDiskUUIDFromVolumeName(session, name))) {
			string = [(id)CFUUIDCreateString(kCFAllocatorDefault, uuid) autorelease];
			CFRelease(uuid);
		}
		CFRelease(session);
	}
	
	return string;
}

- (id) initWithDiskUUID:(NSString*)uuid
{
	if(![uuid length]) {
		[self release];
		return nil;
	}
	
	if((self = [super init])) {
		_uuid = [uuid copy];
		_runLoop = (CFRunLoopRef)CFRetain(CFRunLoopGetCurrent());
	}
	
	return self;
}

- (void) dealloc
{
	[self setDelegate:nil];
	
	if(_runLoop)
	CFRelease(_runLoop);
	[_uuid release];
	
	[super dealloc];
}

static void _DiskDescriptionChangedCallback(DADiskRef disk, CFArrayRef keys, void* context)
{
	NSAutoreleasePool*			pool = [NSAutoreleasePool new];
	DiskWatcher*				self = (DiskWatcher*)context;
	CFDictionaryRef				description;
	CFUUIDRef					inUUID,
								outUUID;
								
	if((inUUID = CFUUIDCreateFromString(kCFAllocatorDefault, (CFStringRef)self->_uuid))) {
		if((description = DADiskCopyDescription(disk))) {
			outUUID = CFDictionaryGetValue(description, kDADiskDescriptionVolumeUUIDKey);
			if(outUUID && CFEqual(outUUID, inUUID))
			[self->_delegate diskWatcherDidUpdateAvailability:self];
			CFRelease(description);
		}
		CFRelease(inUUID);
	}
	
	[pool release];
}

- (void) setDelegate:(id<DiskWatcherDelegate>)delegate
{
	if(delegate && !_delegate) {
		_session = DASessionCreate(kCFAllocatorDefault);
		if(_session) {
			DASessionScheduleWithRunLoop(_session, _runLoop, kCFRunLoopCommonModes);
			DARegisterDiskDescriptionChangedCallback(_session, kDADiskDescriptionMatchVolumeMountable, kDADiskDescriptionWatchVolumePath, _DiskDescriptionChangedCallback, self);
			_delegate = delegate;
		}
		else
		NSLog(@"%s: DASessionCreate() failed", __FUNCTION__);
	}
	else if(!delegate && _delegate) {
		DAUnregisterCallback(_session, _DiskDescriptionChangedCallback, self);
		DASessionUnscheduleFromRunLoop(_session, _runLoop, kCFRunLoopCommonModes);
		CFRelease(_session);
		_delegate = nil;
	}
}

- (BOOL) isDiskAvailable
{
	BOOL					available = NO;
	DASessionRef			session;
	NSString*				name;
	CFUUIDRef				inUUID,
							outUUID;
	
	inUUID = CFUUIDCreateFromString(kCFAllocatorDefault, (CFStringRef)_uuid);
	if(inUUID == NULL)
	return NO;
	
	session = (_delegate ? (DASessionRef)CFRetain(_session) : DASessionCreate(kCFAllocatorDefault));
	if(session) {
		for(name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Volumes" error:NULL]) {
			if(![name hasPrefix:@"."] && (outUUID = _CreateDiskUUIDFromVolumeName(session, name))) {
				available = CFEqual(outUUID, inUUID);
				CFRelease(outUUID);
				if(available)
				break;
			}
		}
		CFRelease(session);
	}
	
	CFRelease(inUUID);
	
	return available;
}

@end
