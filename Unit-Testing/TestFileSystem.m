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
#import <sys/stat.h>
#import <sys/xattr.h>
#import <membership.h>

#import "DiskImageController.h"
#import "DirectoryScanner.h"
#import "DirectoryWatcher.h"
#import "DiskWatcher.h"

#define kDirectoryPath @"/Library/Desktop Pictures"
#define kOtherDirectoryPath @"/Library/Application Support/iWork '08/iWork Tour.app/Contents/Resources/English.lproj"

@interface FileSystemTestCase : SenTestCase <DirectoryWatcherDelegate, DiskWatcherDelegate>
{
	BOOL					_didUpdate;
}
@end

static NSComparisonResult _SortFunction(NSString* path1, NSString* path2, void* context)
{
	return [path1 compare:path2 options:(NSCaseInsensitiveSearch | NSNumericSearch | NSForcedOrderingSearch)];
}

@implementation FileSystemTestCase

- (void) directoryWatcherRootDidChange:(DirectoryWatcher*)watcher
{
	;
}

- (void) directoryWatcher:(DirectoryWatcher*)watcher didUpdate:(NSString*)path recursively:(BOOL)recursively eventID:(FSEventStreamEventId)eventID
{
	_didUpdate = YES;
}

/*- (void) _update:(NSTimer*)timer
{
	NSString*				path = (NSString*)[timer userInfo];
	NSError*				error;
	
	STAssertTrue([[NSFileManager defaultManager] createSymbolicLinkAtPath:[path stringByAppendingPathComponent:@"Test.jpg"] withDestinationPath:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"jpg"] error:&error], [error localizedDescription]);
}

- (void) testWatcher
{
	NSString*				path = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	DirectoryWatcher*		watcher;
	NSError*				error;
	
	STAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:&error], [error localizedDescription]);
	
	watcher = [[DirectoryWatcher alloc] initWithRootDirectory:path latency:0.0 lastEventID:0];
	STAssertNotNil(watcher, nil);
	[watcher setDelegate:self];
	
	_didUpdate = NO;
	STAssertEqualObjects([watcher rootDirectory], path, nil);
	[watcher startWatching];
	STAssertTrue([watcher isWatching], nil);
	[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(_update:) userInfo:path repeats:NO];
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
	[watcher stopWatching];
	STAssertTrue(_didUpdate, nil);
	
	[watcher setDelegate:nil];
	[watcher release];
	
	STAssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:&error], [error localizedDescription]);
}

- (void) testScanner1
{
	NSString*				path = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSArray*				expectedContent;
	NSMutableArray*			content;
	DirectoryScanner*		scanner;
	NSDictionary*			dictionary;
	DirectoryItem*			info;
	DirectoryScanner*		serializedScanner;
	
	expectedContent = [[[NSFileManager defaultManager] subpathsAtPath:kDirectoryPath] sortedArrayUsingFunction:_SortFunction context:NULL];
	
	scanner = [[DirectoryScanner alloc] initWithRootDirectory:kDirectoryPath scanMetadata:NO];
	[scanner setSortPaths:YES];
	STAssertNotNil(scanner, nil);
	STAssertEqualObjects([scanner rootDirectory], kDirectoryPath, nil);
	STAssertEquals([scanner revision], (NSUInteger)0, nil);
	
	STAssertNil([scanner scanAndCompareRootDirectory:0], nil);
	
	dictionary = [scanner scanRootDirectory];
	STAssertNotNil(dictionary, nil);
	STAssertNil([dictionary objectForKey:kDirectoryScannerResultKey_ExcludedPaths], nil);
	STAssertNil([dictionary objectForKey:kDirectoryScannerResultKey_ErrorPaths], nil);
	STAssertEquals([scanner revision], (NSUInteger)1, nil);
	STAssertEquals([scanner numberOfDirectoryItems], [expectedContent count], nil);
	content = [NSMutableArray new];
	for(info in [scanner subpathsOfRootDirectory])
	[content addObject:[info path]];
	STAssertEqualObjects(content, expectedContent, nil);
	[content release];
	content = [NSMutableArray new];
	for(info in scanner)
	[content addObject:[info path]];
	[content sortUsingFunction:_SortFunction context:NULL];
	STAssertEqualObjects(content, expectedContent, nil);
	[content release];
	
	dictionary = [scanner scanAndCompareRootDirectory:0];
	STAssertNotNil(dictionary, nil);
	STAssertEquals([dictionary count], (NSUInteger)0, nil);
	
	[scanner setUserInfo:@"info@pol-online.net" forDirectoryItemAtSubpath:[expectedContent objectAtIndex:0]];
	STAssertEqualObjects([[scanner directoryItemAtSubpath:[expectedContent objectAtIndex:0]] userInfo], @"info@pol-online.net", nil);
	
	[scanner setUserInfo:@"PolKit" forKey:@"pol-online"];
	STAssertEqualObjects([scanner userInfoForKey:@"pol-online"], @"PolKit", nil);
	
	STAssertTrue([scanner writeToFile:path], nil);
	
	serializedScanner = [[DirectoryScanner alloc] initWithFile:path];
	STAssertNotNil(serializedScanner, nil);
	STAssertEquals([serializedScanner revision], (NSUInteger)1, nil);
	content = [NSMutableArray new];
	for(info in [serializedScanner subpathsOfRootDirectory])
	[content addObject:[info path]];
	STAssertEqualObjects(content, expectedContent, nil);
	[content release];
	dictionary = [serializedScanner compare:scanner options:0];
	STAssertNotNil(dictionary, nil);
	STAssertFalse([dictionary count], nil);
	STAssertEqualObjects([[serializedScanner directoryItemAtSubpath:[expectedContent objectAtIndex:0]] userInfo], @"info@pol-online.net", nil);
	STAssertEqualObjects([serializedScanner userInfoForKey:@"pol-online"], @"PolKit", nil);
	[serializedScanner release];
	
	[scanner removeDirectoryItemAtSubpath:[expectedContent objectAtIndex:0]];
	STAssertNil([scanner directoryItemAtSubpath:[expectedContent objectAtIndex:0]], nil);
	
	[scanner setUserInfo:nil forKey:@"pol-online"];
	STAssertNil([scanner userInfoForKey:@"pol-online"], nil);
	
	[scanner release];
}

- (void) testScanner2
{
	DirectoryScanner*		scanner1;
	DirectoryScanner*		scanner2;
	
	scanner1 = [[DirectoryScanner alloc] initWithRootDirectory:kDirectoryPath scanMetadata:NO];
	STAssertNotNil(scanner1, nil);
	
	STAssertNotNil([scanner1 scanRootDirectory], nil);
	STAssertNotNil([scanner1 directoryItemAtSubpath:@"Abstract"], nil);
	STAssertNotNil([scanner1 directoryItemAtSubpath:@"Flow 1.jpg"], nil);
	STAssertNotNil([scanner1 directoryItemAtSubpath:@"Flow 2.jpg"], nil);
	STAssertNotNil([scanner1 directoryItemAtSubpath:@"Solid Colors"], nil);
	STAssertNotNil([scanner1 directoryItemAtSubpath:@"Black & White/Mojave.jpg"], nil);
	STAssertNotNil([scanner1 directoryItemAtSubpath:@"Plants/Bamboo Grove.jpg"], nil);
	
	scanner2 = [[DirectoryScanner alloc] initWithRootDirectory:kDirectoryPath scanMetadata:NO];
	STAssertNotNil(scanner2, nil);
	
	[scanner2 setExclusionPredicate:[DirectoryScanner exclusionPredicateWithPaths:[NSArray arrayWithObjects:@"Solid Colors", [@"Abstract" lowercaseString], [@"Plants/Bamboo Grove.jpg" uppercaseString], nil] names:[NSArray arrayWithObjects:@"Flow 1.jpg", [@"Flow 2.jpg" lowercaseString], [@"Mojave.jpg" uppercaseString], nil]]];
	STAssertEqualObjects([scanner2 exclusionPredicate], [NSPredicate predicateWithFormat:@"$PATH LIKE[c] \"Solid Colors\" OR $PATH LIKE[c] \"abstract\" OR $PATH LIKE[c] \"PLANTS/BAMBOO GROVE.JPG\" OR $NAME LIKE[c] \"Flow 1.jpg\" OR $NAME LIKE[c] \"flow 2.jpg\" OR $NAME LIKE[c] \"MOJAVE.JPG\""], nil);
	
	STAssertNotNil([scanner2 scanRootDirectory], nil);
	STAssertNil([scanner2 directoryItemAtSubpath:@"Abstract"], nil);
	STAssertNil([scanner2 directoryItemAtSubpath:@"Flow 1.jpg"], nil);
	STAssertNil([scanner2 directoryItemAtSubpath:@"Flow 2.jpg"], nil);
	STAssertNil([scanner2 directoryItemAtSubpath:@"Solid Colors"], nil);
	STAssertNil([scanner2 directoryItemAtSubpath:@"Black & White/Mojave.jpg"], nil);
	STAssertNil([scanner2 directoryItemAtSubpath:@"Plants/Bamboo Grove.jpg"], nil);
	
	[scanner2 release];
	[scanner1 release];
}

- (void) testScanner3
{
	NSMutableArray*			expectedContent;
	NSMutableArray*			content;
	DirectoryScanner*		scanner;
	NSDictionary*			dictionary;
	DirectoryItem*			info;
	NSString*				path;
	
	expectedContent = [[NSMutableArray alloc] initWithArray:[[NSFileManager defaultManager] subpathsAtPath:kOtherDirectoryPath]];
	scanner = [[DirectoryScanner alloc] initWithRootDirectory:kOtherDirectoryPath scanMetadata:NO];
	[scanner setSortPaths:YES];
	dictionary = [scanner scanRootDirectory];
	STAssertNotNil(dictionary, nil);
	content = [NSMutableArray new];
	for(info in [scanner subpathsOfRootDirectory])
	[content addObject:[info path]];
	for(path in [dictionary objectForKey:kDirectoryScannerResultKey_ErrorPaths])
	[expectedContent removeObject:path];
	[expectedContent sortUsingFunction:_SortFunction context:NULL];
	STAssertEqualObjects(content, expectedContent, nil);
	[content release];
	[scanner release];
	[expectedContent release];
}

- (void) testScanner4
{
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSString*				scratchPath = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSString*				tmpPath = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSString*				file = [scratchPath stringByAppendingPathComponent:@"file.data"];
	const char*				string1 = "Hello World!";
	const char*				string2 = "Bonjour le Monde!";
	NSDictionary*			attributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSData dataWithBytes:(void*)string1 length:strlen(string1)], @"net.pol-online.foo", [NSData dataWithBytes:(void*)string2 length:strlen(string2)], @"net.pol-online.bar", nil];
	DirectoryScanner*		scanner;
	NSDictionary*			dictionary;
	NSArray*				array;
	DirectoryItem*			item;
	NSError*				error;
	DirectoryScanner*		otherScanner;
	acl_t					acl;
	acl_entry_t				aclEntry;
	acl_permset_t			aclPerms;
	uuid_t					aclQualifier;
	char*					aclText;
	
	STAssertTrue([manager createDirectoryAtPath:scratchPath withIntermediateDirectories:NO attributes:nil error:&error], [error localizedDescription]);
	STAssertTrue([[NSData data] writeToFile:file options:NSAtomicWrite error:&error], [error localizedDescription]);
	STAssertEquals(chmod([file UTF8String], S_IRUSR | S_IWUSR | S_IRGRP), (int)0, nil);
	STAssertEquals(setxattr([file UTF8String], "net.pol-online.foo", string1, strlen(string1), 0, 0), (int)0, nil);
	STAssertEquals(setxattr([file UTF8String], "net.pol-online.bar", string2, strlen(string2), 0, 0), (int)0, nil);
	acl = acl_init(1);
	STAssertEquals(acl_create_entry(&acl, &aclEntry), (int)0, nil);
	STAssertEquals(acl_set_tag_type(aclEntry, ACL_EXTENDED_ALLOW), (int)0, nil);
	STAssertEquals(mbr_gid_to_uuid(getgid(), aclQualifier), (int)0, nil);
	STAssertEquals(acl_set_qualifier(aclEntry, aclQualifier), (int)0, nil);
	STAssertEquals(acl_get_permset(aclEntry, &aclPerms), (int)0, nil);
	STAssertEquals(acl_clear_perms(aclPerms), (int)0, nil);
	STAssertEquals(acl_add_perm(aclPerms, ACL_WRITE_DATA), (int)0, nil);
	STAssertEquals(acl_set_permset(aclEntry, aclPerms), (int)0, nil);
	STAssertEquals(acl_set_file([file UTF8String], ACL_TYPE_EXTENDED, acl), (int)0, nil);
	aclText = acl_to_text(acl, NULL);
	acl_free(acl);
	STAssertEquals(chflags([file UTF8String], UF_IMMUTABLE), (int)0, nil);
	
	scanner = [[DirectoryScanner alloc] initWithRootDirectory:scratchPath scanMetadata:NO];
	dictionary = [scanner scanRootDirectory];
	STAssertNotNil(dictionary, nil);
	STAssertEquals([dictionary count], (NSUInteger)0, nil);
	array = [scanner subpathsOfRootDirectory];
	STAssertEquals([array count], (NSUInteger)1, nil);
	item = [array objectAtIndex:0];
	STAssertFalse([item isDirectory], nil);
	STAssertEquals([item userID], (unsigned int)0, nil);
	STAssertEquals([item groupID], (unsigned int)0, nil);
	STAssertEquals([item permissions], (unsigned short)0, nil);
	STAssertEquals([item userFlags], (unsigned short)0, nil);
	STAssertEqualObjects([item ACLText], nil, nil);
	STAssertEqualObjects([item extendedAttributes], nil, nil);
	[scanner release];
	
	scanner = [[DirectoryScanner alloc] initWithRootDirectory:scratchPath scanMetadata:YES];
	dictionary = [scanner scanRootDirectory];
	STAssertNotNil(dictionary, nil);
	STAssertEquals([dictionary count], (NSUInteger)0, nil);
	array = [scanner subpathsOfRootDirectory];
	STAssertEquals([array count], (NSUInteger)1, nil);
	item = [array objectAtIndex:0];
	STAssertFalse([item isDirectory], nil);
	STAssertEquals([item userID], (unsigned int)getuid(), nil);
	STAssertEquals([item groupID], (unsigned int)0, nil);
	STAssertEquals([item permissions], (unsigned short)(S_IRUSR | S_IWUSR | S_IRGRP), nil);
	STAssertEquals([item userFlags], (unsigned short)UF_IMMUTABLE, nil);
	STAssertEqualObjects([item ACLText], [NSString stringWithUTF8String:aclText], nil);
	STAssertEqualObjects([item extendedAttributes], attributes, nil);
	
	STAssertTrue([scanner writeToFile:tmpPath], nil);
	otherScanner = [[DirectoryScanner alloc] initWithFile:tmpPath];
	STAssertNotNil(otherScanner, nil);
	dictionary = [scanner compare:otherScanner options:0];
	STAssertNotNil(dictionary, nil);
	STAssertEquals([dictionary count], (NSUInteger)0, nil);
	STAssertEquals(chflags([file UTF8String], 0), (int)0, nil);
	STAssertEquals(removexattr([file UTF8String], "net.pol-online.bar", 0), (int)0, nil);
	STAssertEquals(chflags([file UTF8String], UF_IMMUTABLE), (int)0, nil);
	dictionary = [scanner scanRootDirectory];
	STAssertNotNil(dictionary, nil);
	STAssertEquals([dictionary count], (NSUInteger)0, nil);
	dictionary = [scanner compare:otherScanner options:0];
	STAssertNotNil(dictionary, nil);
	STAssertEquals([dictionary count], (NSUInteger)1, nil);
	STAssertEquals([[dictionary objectForKey:kDirectoryScannerResultKey_ModifiedItems_Metadata] count], (NSUInteger)1, nil);
	[otherScanner release];
	STAssertTrue([manager removeItemAtPath:tmpPath error:&error], [error localizedDescription]);
	
	acl_free(aclText);
	STAssertEquals(chflags([file UTF8String], 0), (int)0, nil);
	STAssertTrue([manager removeItemAtPath:scratchPath error:&error], [error localizedDescription]);
}*/

- (void) diskWatcherDidUpdateAvailability:(DiskWatcher*)watcher
{
	_didUpdate = YES;
}

- (void) _mount:(NSTimer*)timer
{
	DiskImageController*	controller = [DiskImageController sharedDiskImageController];
	NSString*				mountPath;
	
	mountPath = [controller mountDiskImage:[timer userInfo] atPath:nil usingShadowFile:nil password:nil private:NO verify:NO];
	STAssertNotNil(mountPath, nil);
	STAssertTrue([controller unmountDiskImageAtPath:mountPath force:NO], nil);
}

- (void) testDiskWatcher
{
	DiskImageController*	controller = [DiskImageController sharedDiskImageController];
	NSString*				imagePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"Volume" ofType:@"dmg"];
	NSString*				mountPath;
	NSString*				uuid;
	DiskWatcher*			watcher;
	
	mountPath = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:nil private:NO verify:NO];
	STAssertNotNil(mountPath, nil);
	uuid = [DiskWatcher diskUUIDForVolumeName:[mountPath lastPathComponent]];
	STAssertNotNil(uuid, nil);
	STAssertTrue([controller unmountDiskImageAtPath:mountPath force:NO], nil);
	
	watcher = [[DiskWatcher alloc] initWithDiskUUID:uuid];
	STAssertNotNil(watcher, nil);
	STAssertFalse([watcher isDiskAvailable], nil);
	mountPath = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:nil private:NO verify:NO];
	STAssertNotNil(mountPath, nil);
	STAssertTrue([watcher isDiskAvailable], nil);
	STAssertTrue([controller unmountDiskImageAtPath:mountPath force:NO], nil);
	[watcher release];
	
	_didUpdate = NO;
	watcher = [[DiskWatcher alloc] initWithDiskUUID:uuid];
	[watcher setDelegate:self];
	STAssertNotNil(watcher, nil);
	[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(_mount:) userInfo:imagePath repeats:NO];
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
	[watcher release];
	STAssertTrue(_didUpdate, nil);
}

@end
