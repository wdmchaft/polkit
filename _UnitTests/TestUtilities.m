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

#import "UnitTesting.h"
#import "Keychain.h"
#import "MD5.h"
#import "Task.h"
#import "DiskImageController.h"
#import "SVNClient.h"
#import "LoginItems.h"
#import "SystemInfo.h"

#define kKeychainService @"unit-testing"
#define kLogin @"polkit"
#define kPassword @"info@pol-online.net"
#define kSVNURL @"http://polkit.googlecode.com/svn/trunk/_UnitTests"
#define kURLWithoutPassword @"ftp://foo@example.com/path"
#define kURLWithPassword @"ftp://foo:bar@example.com/path"

@interface UnitTests_Utilities : UnitTest
@end

@implementation UnitTests_Utilities

- (void) testDataStream
{
	; //DataStream class is tested through FileTransferController class
}

- (void) testKeychain
{
	AssertTrue([[Keychain sharedKeychain] addGenericPassword:kPassword forService:kKeychainService account:kLogin], nil);
	AssertEqualObjects([[Keychain sharedKeychain] genericPasswordForService:kKeychainService account:kLogin], kPassword, nil);
	AssertTrue([[Keychain sharedKeychain] removeGenericPasswordForService:kKeychainService account:kLogin], nil);
	AssertNil([[Keychain sharedKeychain] genericPasswordForService:kKeychainService account:kLogin], nil);
	
	AssertTrue([[Keychain sharedKeychain] addPasswordForURL:[NSURL URLWithString:kURLWithPassword]], nil);
	AssertEqualObjects([[Keychain sharedKeychain] URLWithPasswordForURL:[NSURL URLWithString:kURLWithoutPassword]], [NSURL URLWithString:kURLWithPassword], nil);
	AssertTrue([[Keychain sharedKeychain] removePasswordForURL:[NSURL URLWithString:kURLWithoutPassword]], nil);
	AssertEqualObjects([[Keychain sharedKeychain] URLWithPasswordForURL:[NSURL URLWithString:kURLWithoutPassword]], [NSURL URLWithString:kURLWithoutPassword], nil);
}

- (void) testLoginItems
{
	AssertTrue([[LoginItems sharedLoginItems] removeItemWithDisplayName:@"Pol-Online"], nil);
	AssertFalse([[LoginItems sharedLoginItems] hasItemWithDisplayName:@"Pol-Online"], nil);
	AssertTrue([[LoginItems sharedLoginItems] addItemWithDisplayName:@"Pol-Online" url:[NSURL fileURLWithPath:@"/Applications/Safari.app"] hidden:NO], nil);
	AssertTrue([[LoginItems sharedLoginItems] hasItemWithDisplayName:@"Pol-Online"], nil);
	AssertTrue([[LoginItems sharedLoginItems] removeItemWithDisplayName:@"Pol-Online"], nil);
	AssertFalse([[LoginItems sharedLoginItems] hasItemWithDisplayName:@"Pol-Online"], nil);
}

- (void) testMD5Computation
{
	NSData*					data;
	MD5						dataMD5,
							expectedMD5;
	NSString*				string;
	
	data = [[NSData alloc] initWithContentsOfFile:@"Image.jpg"];
	AssertNotNil(data, nil);
	dataMD5 = MD5WithData(data);
	[data release];
	
	//Generated with 'openssl dgst -md5 Image.jpg'
	string = [NSString stringWithContentsOfFile:@"Image.md5" encoding:NSUTF8StringEncoding error:NULL];
	AssertTrue([string isEqualToString:[MD5ToString(&dataMD5) lowercaseString]], nil);
	expectedMD5 = MD5FromString(string);
	AssertTrue(MD5EqualToMD5(&dataMD5, &expectedMD5), nil);
}

- (void) testMD5StringConversion
{
	NSString*				string = @"f430e8d7a52c4fc38fef381ec6ffe594";
	MD5						md5;
	
	md5 = MD5FromString(string);
	
	AssertTrue([MD5ToString(&md5) isEqualToString:[string uppercaseString]], nil);
}

- (void) testTask
{
	NSString*	result;
	
	result = [Task runWithToolPath:@"/usr/bin/grep" arguments:[NSArray arrayWithObject:@"france"] inputString:@"bonjour!\nvive la france!\nau revoir!" timeOut:0.0];
	AssertEqualObjects(result, @"vive la france!\n", nil);
	
	result = [Task runWithToolPath:@"/bin/sleep" arguments:[NSArray arrayWithObject:@"2"] inputString:nil timeOut:1.0];
	AssertNil(result, nil);
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
	
	sourcePath = @".";
	imagePath = [imagePath stringByAppendingPathExtension:@"dmg"];
	AssertTrue([controller makeCompressedDiskImageAtPath:imagePath withName:nil contentsOfDirectory:sourcePath password:kPassword], nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:nil private:NO verify:YES];
	AssertNil(mountPoint, nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:kPassword private:NO verify:YES];
	AssertNotNil(mountPoint, nil);
	AssertTrue([[manager contentsOfDirectoryAtPath:mountPoint error:NULL] count] >= [[manager contentsOfDirectoryAtPath:sourcePath error:NULL] count], nil);
	AssertTrue([controller unmountDiskImageAtPath:mountPoint force:NO], nil);
	sleep(1);
	AssertNil([controller infoForDiskImageAtPath:imagePath password:nil], nil);
	AssertNotNil([controller infoForDiskImageAtPath:imagePath password:kPassword], nil);
	AssertTrue([manager removeItemAtPath:imagePath error:&error], [error localizedDescription]);
	
	sourcePath = @"Image.jpg";
	imagePath = [[imagePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"dmg"];
	AssertTrue([controller makeDiskImageAtPath:imagePath withName:nil size:(10 * 1024) password:nil], nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:nil private:NO verify:NO];
	AssertNotNil(mountPoint, nil);
	AssertTrue([manager copyItemAtPath:sourcePath toPath:[mountPoint stringByAppendingPathComponent:[sourcePath lastPathComponent]] error:&error], [error localizedDescription]);
	AssertTrue([controller unmountDiskImageAtPath:mountPoint force:NO], nil);
	sleep(1);
	AssertNotNil([controller infoForDiskImageAtPath:imagePath password:nil], nil);
	AssertTrue([controller makeCompressedDiskImageAtPath:imagePath2 withDiskImage:imagePath password:nil], nil);
	AssertTrue([manager removeItemAtPath:imagePath2 error:&error], [error localizedDescription]);
	AssertTrue([manager removeItemAtPath:imagePath error:&error], [error localizedDescription]);
	
	sourcePath = @"Image.jpg";
	imagePath = [[imagePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"sparseimage"];
	AssertTrue([controller makeSparseDiskImageAtPath:imagePath withName:nil size:(10 * 1024) password:nil], nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:nil private:NO verify:YES];
	AssertNotNil(mountPoint, nil);
	AssertTrue([manager copyItemAtPath:sourcePath toPath:[mountPoint stringByAppendingPathComponent:[sourcePath lastPathComponent]] error:&error], [error localizedDescription]);
	AssertTrue([controller unmountDiskImageAtPath:mountPoint force:NO], nil);
	sleep(1);
	AssertNotNil([controller infoForDiskImageAtPath:imagePath password:nil], nil);
	AssertTrue([manager removeItemAtPath:imagePath error:&error], [error localizedDescription]);
	
	sourcePath = @"Image.jpg";
	imagePath = [[imagePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"sparsebundle"];
	AssertTrue([controller makeSparseBundleDiskImageAtPath:imagePath withName:nil password:kPassword], nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:kPassword private:NO verify:NO];
	AssertNotNil(mountPoint, nil);
	AssertTrue([manager copyItemAtPath:sourcePath toPath:[mountPoint stringByAppendingPathComponent:[sourcePath lastPathComponent]] error:&error], [error localizedDescription]);
	AssertTrue([controller unmountDiskImageAtPath:mountPoint force:NO], nil);
	sleep(1);
	AssertNil([controller infoForDiskImageAtPath:imagePath password:nil], nil);
	AssertNotNil([controller infoForDiskImageAtPath:imagePath password:kPassword], nil);
	AssertTrue([manager removeItemAtPath:imagePath error:&error], [error localizedDescription]);
}

- (void) testSVN
{
	NSString*				path = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSError*				error;
	SVNClient*				client;
	
	AssertNotNil([SVNClient infoForURL:kSVNURL], nil);
	
	AssertTrue([SVNClient exportURL:kSVNURL toPath:path], nil);
	AssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:&error], [error localizedDescription]);
	
	AssertTrue([SVNClient checkOutURL:kSVNURL toPath:path], nil);
	AssertNotNil([SVNClient infoForPath:path], nil);
	
	client = [[SVNClient alloc] initWithRepositoryPath:path];
	AssertNotNil(client, nil);
	AssertNotNil([client infoForPath:@"Image.jpg"], nil);
	AssertNotNil([client statusForPath:@"."], nil);
	AssertTrue([client setProperty:kPassword forPath:@"." key:kLogin], nil);
	AssertEqualObjects([client propertyForPath:@"." key:kLogin], kPassword, nil);
	AssertTrue([[client statusForPath:@"."] count], nil);
	AssertTrue([client removePropertyForPath:@"." key:kLogin], nil);
	AssertFalse([[client statusForPath:@"."] count], nil);
	AssertTrue([client updatePath:@"UnitTests.xcodeproj" revision:([client updatePath:@"UnitTests.xcodeproj"] - 1)], nil);
	[client release];
	
	AssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:&error], [error localizedDescription]);
}

- (void) testSystemInfo
{
	AssertNotNil([SystemInfo sharedSystemInfo], nil);
}

@end
