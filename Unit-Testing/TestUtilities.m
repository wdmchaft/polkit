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

#import "Keychain.h"
#import "MD5.h"
#import "Task.h"
#import "DiskImageController.h"
#import "SVNClient.h"
#import "LoginItems.h"
#import "SystemInfo.h"

#define kKeychainService @"unit-testing"
#define kKeychainAccount @"polkit"
#define kKeychainPassword @"info@pol-online.net"
#define kSVNURL @"http://polkit.googlecode.com/svn/trunk/Unit-Testing"
#define kURLWithoutPassword @"ftp://foo@example.com/path"
#define kURLWithPassword @"ftp://foo:bar@example.com/path"

@interface UtilitiesTestCase : SenTestCase
@end

@implementation UtilitiesTestCase

- (void) testDataStream
{
	NSLog(@"DataStream class is tested through FileTransferController class");
}

- (void) testKeychain
{
	STAssertTrue([[Keychain sharedKeychain] addGenericPassword:kKeychainPassword forService:kKeychainService account:kKeychainAccount], nil);
	STAssertEqualObjects([[Keychain sharedKeychain] genericPasswordForService:kKeychainService account:kKeychainAccount], kKeychainPassword, nil);
	STAssertTrue([[Keychain sharedKeychain] removeGenericPasswordForService:kKeychainService account:kKeychainAccount], nil);
	STAssertNil([[Keychain sharedKeychain] genericPasswordForService:kKeychainService account:kKeychainAccount], nil);
	
	STAssertTrue([[Keychain sharedKeychain] addPasswordForURL:[NSURL URLWithString:kURLWithPassword]], nil);
	STAssertEqualObjects([[Keychain sharedKeychain] URLWithPasswordForURL:[NSURL URLWithString:kURLWithoutPassword]], [NSURL URLWithString:kURLWithPassword], nil);
	STAssertTrue([[Keychain sharedKeychain] removePasswordForURL:[NSURL URLWithString:kURLWithoutPassword]], nil);
	STAssertEqualObjects([[Keychain sharedKeychain] URLWithPasswordForURL:[NSURL URLWithString:kURLWithoutPassword]], [NSURL URLWithString:kURLWithoutPassword], nil);
}

- (void) testLoginItems
{
	STAssertTrue([[LoginItems sharedLoginItems] removeItemWithDisplayName:@"Pol-Online"], nil);
	STAssertTrue([[LoginItems sharedLoginItems] addItemWithDisplayName:@"Pol-Online" url:[NSURL fileURLWithPath:@"/Applications/Safari.app"] hidden:NO], nil);
	STAssertTrue([[LoginItems sharedLoginItems] removeItemWithDisplayName:@"Pol-Online"], nil);
}

- (void) testMD5Computation
{
	NSData*					data;
	MD5						dataMD5,
							expectedMD5;
	NSString*				string;
	
	data = [[NSData alloc] initWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"jpg"]];
	STAssertNotNil(data, nil);
	dataMD5 = MD5WithData(data);
	[data release];
	
	//Generated with 'openssl dgst -md5 Image.jpg'
	string = [NSString stringWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"md5"] encoding:NSUTF8StringEncoding error:NULL];
	STAssertTrue([string isEqualToString:[MD5ToString(&dataMD5) lowercaseString]], nil);
	expectedMD5 = MD5FromString(string);
	STAssertTrue(MD5EqualToMD5(&dataMD5, &expectedMD5), nil);
}

- (void) testMD5StringConversion
{
	NSString*				string = @"f430e8d7a52c4fc38fef381ec6ffe594";
	MD5						md5;
	
	md5 = MD5FromString(string);
	
	STAssertTrue([MD5ToString(&md5) isEqualToString:[string uppercaseString]], nil);
}

- (void) testTask
{
	NSString*	result;
	
	result = [Task runWithToolPath:@"/usr/bin/grep" arguments:[NSArray arrayWithObject:@"france"] inputString:@"bonjour!\nvive la france!\nau revoir!" timeOut:0.0];
	STAssertEqualObjects(result, @"vive la france!\n", nil);
	
	result = [Task runWithToolPath:@"/bin/sleep" arguments:[NSArray arrayWithObject:@"2"] inputString:nil timeOut:1.0];
	STAssertNil(result, nil);
}

- (void) testDiskImage
{
	DiskImageController*	controller = [DiskImageController sharedDiskImageController];
	NSString*				imagePath = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSString*				imagePath2 = [[@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]] stringByAppendingPathExtension:@"dmg"];
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSString*				sourcePath;
	NSError*				error;
	NSString*				mountPoint;
	
	sourcePath = [[NSBundle bundleForClass:[self class]] resourcePath];
	imagePath = [imagePath stringByAppendingPathExtension:@"dmg"];
	STAssertTrue([controller makeCompressedDiskImageAtPath:imagePath withName:nil contentsOfDirectory:sourcePath password:kKeychainPassword], nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:nil private:NO verify:YES];
	STAssertNil(mountPoint, nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:kKeychainPassword private:NO verify:YES];
	STAssertNotNil(mountPoint, nil);
	STAssertTrue([[manager contentsOfDirectoryAtPath:mountPoint error:NULL] count] >= [[manager contentsOfDirectoryAtPath:sourcePath error:NULL] count], nil);
	STAssertTrue([controller unmountDiskImageAtPath:mountPoint force:NO], nil);
	STAssertNil([controller infoForDiskImageAtPath:imagePath password:nil], nil);
	STAssertNotNil([controller infoForDiskImageAtPath:imagePath password:kKeychainPassword], nil);
	STAssertTrue([manager removeItemAtPath:imagePath error:&error], [error localizedDescription]);
	
	sourcePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"jpg"];
	imagePath = [[imagePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"dmg"];
	STAssertTrue([controller makeDiskImageAtPath:imagePath withName:nil size:(10 * 1024) password:nil], nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:nil private:NO verify:NO];
	STAssertNotNil(mountPoint, nil);
	STAssertTrue([manager copyItemAtPath:sourcePath toPath:[mountPoint stringByAppendingPathComponent:[sourcePath lastPathComponent]] error:&error], [error localizedDescription]);
	STAssertTrue([controller unmountDiskImageAtPath:mountPoint force:NO], nil);
	STAssertNotNil([controller infoForDiskImageAtPath:imagePath password:nil], nil);
	STAssertTrue([controller makeCompressedDiskImageAtPath:imagePath2 withDiskImage:imagePath password:nil], nil);
	STAssertTrue([manager removeItemAtPath:imagePath2 error:&error], [error localizedDescription]);
	STAssertTrue([manager removeItemAtPath:imagePath error:&error], [error localizedDescription]);
	
	sourcePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"jpg"];
	imagePath = [[imagePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"sparseimage"];
	STAssertTrue([controller makeSparseDiskImageAtPath:imagePath withName:nil size:(10 * 1024) password:nil], nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:nil private:NO verify:YES];
	STAssertNotNil(mountPoint, nil);
	STAssertTrue([manager copyItemAtPath:sourcePath toPath:[mountPoint stringByAppendingPathComponent:[sourcePath lastPathComponent]] error:&error], [error localizedDescription]);
	STAssertTrue([controller unmountDiskImageAtPath:mountPoint force:NO], nil);
	STAssertNotNil([controller infoForDiskImageAtPath:imagePath password:nil], nil);
	STAssertTrue([manager removeItemAtPath:imagePath error:&error], [error localizedDescription]);
	
	sourcePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"jpg"];
	imagePath = [[imagePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"sparsebundle"];
	STAssertTrue([controller makeSparseBundleDiskImageAtPath:imagePath withName:nil password:kKeychainPassword], nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:kKeychainPassword private:NO verify:NO];
	STAssertNotNil(mountPoint, nil);
	STAssertTrue([manager copyItemAtPath:sourcePath toPath:[mountPoint stringByAppendingPathComponent:[sourcePath lastPathComponent]] error:&error], [error localizedDescription]);
	STAssertTrue([controller unmountDiskImageAtPath:mountPoint force:NO], nil);
	STAssertNil([controller infoForDiskImageAtPath:imagePath password:nil], nil);
	STAssertNotNil([controller infoForDiskImageAtPath:imagePath password:kKeychainPassword], nil);
	STAssertTrue([manager removeItemAtPath:imagePath error:&error], [error localizedDescription]);
}

- (void) testSVN
{
	NSString*				path = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSError*				error;
	SVNClient*				client;
	
	STAssertNotNil([SVNClient infoForURL:kSVNURL], nil);
	
	STAssertTrue([SVNClient exportURL:kSVNURL toPath:path], nil);
	STAssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:&error], [error localizedDescription]);
	
	STAssertTrue([SVNClient checkOutURL:kSVNURL toPath:path], nil);
	STAssertNotNil([SVNClient infoForPath:path], nil);
	
	client = [[SVNClient alloc] initWithRepositoryPath:path];
	STAssertNotNil(client, nil);
	STAssertNotNil([client infoForPath:@"Image.jpg"], nil);
	STAssertNotNil([client statusForPath:@"."], nil);
	STAssertTrue([client setProperty:kKeychainPassword forPath:@"." key:kKeychainAccount], nil);
	STAssertEqualObjects([client propertyForPath:@"." key:kKeychainAccount], kKeychainPassword, nil);
	STAssertTrue([[client statusForPath:@"."] count], nil);
	STAssertTrue([client removePropertyForPath:@"." key:kKeychainAccount], nil);
	STAssertFalse([[client statusForPath:@"."] count], nil);
	STAssertTrue([client updatePath:@"Unit-Testing.xcodeproj" revision:([client updatePath:@"Unit-Testing.xcodeproj"] - 1)], nil);
	[client release];
	
	STAssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:&error], [error localizedDescription]);
}

- (void) testSystemInfo
{
	STAssertNotNil([SystemInfo sharedSystemInfo], nil);
}

@end
