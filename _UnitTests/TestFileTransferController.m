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
#import "FileTransferController.h"
#import "Keychain.h"
#import "NSURL+Parameters.h"

@interface UnitTests_FileTransferController : UnitTest <FileTransferControllerDelegate>
@end

@implementation UnitTests_FileTransferController

- (NSArray*) _testURLsForProtocol:(NSString*)protocol
{
	static NSMutableDictionary*	servers = nil;
	NSString*					string;
	NSArray*					components;
	NSMutableArray*				array;
	
	if(servers == nil) {
		servers = [NSMutableDictionary new];
		
		string = [[Keychain sharedKeychain] genericPasswordForService:@"PolKit" account:@"TestURLs"];
		for(string in [string componentsSeparatedByString:@"\n"]) {
			components = [string componentsSeparatedByString:@" "];
			if([components count] == 2) {
				array = [servers objectForKey:[components objectAtIndex:0]];
				if(array == nil) {
					array = [NSMutableArray new];
					[servers setObject:array forKey:[components objectAtIndex:0]];
					[array release];
				}
				[array addObject:[NSURL URLWithString:[components objectAtIndex:1]]];
			}
		}
	}
	
	array = [servers objectForKey:protocol];
	if(array == nil)
	[self logMessage:@"WARNING: No test server for \"%@\" protocol", protocol];
	
	return array;
}

- (void) fileTransferControllerDidFail:(FileTransferController*)controller withError:(NSError*)error
{
	[self logMessage:@"[Error %i] %@\n%@", [error code], [error localizedDescription], [error userInfo]];
}

- (void) _testURL:(NSURL*)url
{
	NSAutoreleasePool*			pool = [NSAutoreleasePool new];
	NSString*					filePath = [[@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]] stringByAppendingPathExtension:@"jpg"];
	NSString*					imagePath = @"Resources/Image.jpg";
	FileTransferController*		controller;
	NSError*					error;
	NSData*						sourceData;
	NSData*						destinationData;
	
	if(!url)
	goto Exit;
	
	controller = [FileTransferController fileTransferControllerWithURL:url];
	AssertNotNil(controller, nil);
	if([controller isKindOfClass:[HTTPTransferController class]])
	[(HTTPTransferController*)controller setSSLCertificateValidationDisabled:YES];
	[controller setDelegate:self];
	
	if([controller respondsToSelector:@selector(contentsOfDirectoryAtPath:)] && ![controller contentsOfDirectoryAtPath:nil]) {
		[self logMessage:@"WARNING: \"%@\" is not reachable", [url URLByDeletingPassword]];
		goto Exit;
	}
	
	AssertTrue([controller uploadFileFromPath:imagePath toPath:@"Test.jpg"], nil);
	if([controller respondsToSelector:@selector(deleteFileAtPath:)])
	AssertTrue([controller deleteFileAtPath:@"Test.jpg"], nil);
	if([controller respondsToSelector:@selector(createDirectoryAtPath:)]) {
		AssertTrue([controller createDirectoryAtPath:@"Folder1"], nil);
		if([controller respondsToSelector:@selector(deleteDirectoryRecursivelyAtPath:)])
		AssertTrue([controller deleteDirectoryRecursivelyAtPath:@"Folder1"], nil);
		else if([controller respondsToSelector:@selector(deleteDirectoryAtPath:)])
		AssertTrue([controller deleteDirectoryAtPath:@"Folder1"], nil);
	}
	
	if([controller respondsToSelector:@selector(createDirectoryAtPath:)]) {
		AssertTrue([controller createDirectoryAtPath:@"Folder2"], nil);
		AssertTrue([controller uploadFileFromPath:imagePath toPath:@"Test.jpg"], nil);
		if([controller respondsToSelector:@selector(movePath:toPath:)] && ![[url host] isEqualToString:@"ftp.drivehq.com"]) {
			AssertTrue([controller movePath:@"Test.jpg" toPath:@"Folder2/Temp.jpg"], nil);
			if([controller respondsToSelector:@selector(deleteFileAtPath:)])
			AssertTrue([controller deleteFileAtPath:@"Folder2/Temp.jpg"], nil);
		}
		else if([controller respondsToSelector:@selector(deleteFileAtPath:)])
		AssertTrue([controller deleteFileAtPath:@"Test.jpg"], nil);
		if([controller respondsToSelector:@selector(deleteDirectoryRecursivelyAtPath:)])
		AssertTrue([controller deleteDirectoryRecursivelyAtPath:@"Folder2"], nil);
		else if([controller respondsToSelector:@selector(deleteDirectoryAtPath:)])
		AssertTrue([controller deleteDirectoryAtPath:@"Folder2"], nil);
	}
	
	AssertTrue([controller uploadFileFromPath:imagePath toPath:@"Test.jpg"], nil);
	AssertTrue([controller downloadFileFromPath:@"Test.jpg" toPath:filePath], nil);
	AssertTrue([controller uploadFileFromPath:imagePath toPath:@"Test.jpg"], nil);
	AssertTrue([controller downloadFileFromPath:@"Test.jpg" toPath:filePath], nil);
	sourceData = [NSData dataWithContentsOfFile:imagePath];
	destinationData = [NSData dataWithContentsOfFile:filePath];
	AssertEquals([destinationData length], [sourceData length], nil);
	if([destinationData length] == [sourceData length])
	AssertTrue([destinationData isEqualToData:sourceData], nil);
	AssertTrue([[NSFileManager defaultManager] removeItemAtPath:filePath error:&error], [error localizedDescription]);
	
	if([controller respondsToSelector:@selector(contentsOfDirectoryAtPath:)]) {
		AssertNotNil([controller contentsOfDirectoryAtPath:nil], nil);
		[controller setDelegate:nil];
		AssertNil([controller contentsOfDirectoryAtPath:@"invalid-directory"], nil);
		[controller setDelegate:self];
	}
	if([controller respondsToSelector:@selector(createDirectoryAtPath:)]) {
		AssertTrue([controller createDirectoryAtPath:@"Folder"], nil);
		[controller setDelegate:nil];
		AssertFalse([controller createDirectoryAtPath:@"Folder"], nil);
		[controller setDelegate:self];
		if([controller respondsToSelector:@selector(contentsOfDirectoryAtPath:)]) {
			BOOL isSubset = [[NSSet setWithObjects:@"Test.jpg", @"Folder", nil] isSubsetOfSet:[NSSet setWithArray:[[controller contentsOfDirectoryAtPath:nil] allKeys]]];
			AssertTrue(isSubset, nil);
		}
		if([controller respondsToSelector:@selector(movePath:toPath:)] && ![[url host] isEqualToString:@"ftp.drivehq.com"]) {
			AssertTrue([controller movePath:@"Test.jpg" toPath:@"Folder/NewTest.jpg"], nil);
			if([controller respondsToSelector:@selector(contentsOfDirectoryAtPath:)])
			AssertEqualObjects([[controller contentsOfDirectoryAtPath:@"Folder"] allKeys], [NSArray arrayWithObject:@"NewTest.jpg"], nil);
			AssertTrue([controller movePath:@"Folder/NewTest.jpg" toPath:@"Test.jpg"], nil);
		}
		if([controller respondsToSelector:@selector(copyPath:toPath:)]) {
			AssertTrue([controller copyPath:@"Test.jpg" toPath:@"Folder/~Test.jpg"], nil);
			AssertTrue([controller copyPath:@"Test.jpg" toPath:@"Folder/~Test.jpg"], nil);
			if([controller respondsToSelector:@selector(movePath:toPath:)] && ![[url host] isEqualToString:@"www.box.net"]) {
				AssertTrue([controller copyPath:@"Test.jpg" toPath:@"Folder/Test-2.jpg"], nil);
				AssertTrue([controller movePath:@"Folder/Test-2.jpg" toPath:@"Folder/~Test.jpg"], nil);
			}
			if([controller respondsToSelector:@selector(deleteFileAtPath:)])
			AssertTrue([controller deleteFileAtPath:@"Folder/~Test.jpg"], nil);
		}
		if([controller respondsToSelector:@selector(deleteDirectoryRecursivelyAtPath:)]) {
			AssertTrue([controller deleteDirectoryRecursivelyAtPath:@"Folder"], nil);
			AssertTrue([controller deleteDirectoryRecursivelyAtPath:@"Folder"], nil);
		}
		else if([controller respondsToSelector:@selector(deleteDirectoryAtPath:)]) {
			AssertTrue([controller deleteDirectoryAtPath:@"Folder"], nil);
			if(![controller isKindOfClass:[FTPTransferController class]] && ![controller isKindOfClass:[FTPSTransferController class]]) {
				[controller setDelegate:nil];
				AssertTrue([controller deleteDirectoryAtPath:@"Folder"], nil);
				[controller setDelegate:self];
			}
		}
	}
	else {
		if([controller respondsToSelector:@selector(movePath:toPath:)]) {
			AssertTrue([controller movePath:@"Test.jpg" toPath:@"NewTest.jpg"], nil);
			AssertTrue([controller movePath:@"NewTest.jpg" toPath:@"Test.jpg"], nil);
		}
		if([controller respondsToSelector:@selector(copyPath:toPath:)]) {
			AssertTrue([controller copyPath:@"Test.jpg" toPath:@"~Test.jpg"], nil);
			AssertTrue([controller copyPath:@"Test.jpg" toPath:@"~Test.jpg"], nil);
			if([controller respondsToSelector:@selector(deleteFileAtPath:)])
			AssertTrue([controller deleteFileAtPath:@"~Test.jpg"], nil);
		}
	}
	if([controller respondsToSelector:@selector(deleteFileAtPath:)]) {
		AssertTrue([controller deleteFileAtPath:@"Test.jpg"], nil);
		if(![controller isKindOfClass:[FTPTransferController class]] && ![controller isKindOfClass:[FTPSTransferController class]]) {
			[controller setDelegate:nil];
			AssertTrue([controller deleteFileAtPath:@"Test.jpg"], nil);
			[controller setDelegate:self];
		}
	}
	
	[controller setEncryptionPassword:@"info@pol-online.net"];
	AssertTrue([controller uploadFileFromPath:imagePath toPath:@"Test.data"], nil);
	AssertTrue([controller downloadFileFromPath:@"Test.data" toPath:filePath], nil);
	sourceData = [NSData dataWithContentsOfFile:imagePath];
	destinationData = [NSData dataWithContentsOfFile:filePath];
	AssertEquals([destinationData length], [sourceData length], nil);
	if([destinationData length] == [sourceData length])
	AssertTrue([destinationData isEqualToData:sourceData], nil);
	AssertTrue([[NSFileManager defaultManager] removeItemAtPath:filePath error:&error], [error localizedDescription]);
	if([controller respondsToSelector:@selector(deleteFileAtPath:)])
	AssertTrue([controller deleteFileAtPath:@"Test.data"], nil);
	[controller setEncryptionPassword:nil];
	
	[controller setDelegate:nil];
	
Exit:
	[pool release];
}

- (void) _testDigest:(BOOL)encryption
{
	NSString*					imagePath = @"Resources/Image.jpg";
	NSString*					fileName = [[NSProcessInfo processInfo] globallyUniqueString];
	NSString*					tmpPath = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	FileTransferController*		controller;
	NSError*					error;
	NSData*						data1;
	NSData*						data2;
	
	controller = [FileTransferController fileTransferControllerWithURL:[NSURL fileURLWithPath:@"/tmp"]];
	AssertNotNil(controller, nil);
	[controller setDelegate:self];
	[controller setDigestComputation:YES];
	if(encryption)
	[controller setEncryptionPassword:@"info@pol-online.net"];
	
	AssertTrue([controller uploadFileFromPath:imagePath toPath:fileName], nil);
	data1 = [controller lastTransferDigestData];
	AssertNotNil(data1, nil);
	AssertTrue([controller downloadFileFromPath:fileName toPath:tmpPath], nil);
	data2 = [controller lastTransferDigestData];
	AssertNotNil(data2, nil);
	
	AssertEqualObjects(data1, data2, nil);
	
	//HACK: We should read Image.md5 instead
	AssertEqualObjects(@"<f430e8d7 a52c4fc3 8fef381e c6ffe594>", [data1 description], nil);
	AssertEqualObjects(@"<f430e8d7 a52c4fc3 8fef381e c6ffe594>", [data2 description], nil);
	
	AssertTrue([controller deleteFileAtPath:tmpPath], nil);
	AssertTrue([[NSFileManager defaultManager] removeItemAtPath:tmpPath error:&error], [error localizedDescription]);
	
	if(encryption)
	[controller setEncryptionPassword:nil];
	[controller setDigestComputation:NO];
	[controller setDelegate:nil];
}

- (void) testDigest
{
	[self _testDigest:NO];
}

- (void) testDigestWithEncryption
{
	[self _testDigest:YES];
}

- (void) testEncryption
{
	NSString*					imagePath = @"Resources/Image.jpg";
	NSString*					fileName = [[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingPathExtension:@"data"];
	FileTransferController*		controller;
	NSData*						data1;
	NSData*						data2;
	
	controller = [FileTransferController fileTransferControllerWithURL:[NSURL fileURLWithPath:@"/tmp"]];
	AssertNotNil(controller, nil);
	[controller setDelegate:self];
	[controller setEncryptionPassword:@"info@pol-online.net"];
	
	AssertTrue([controller uploadFileFromPath:imagePath toPath:fileName], nil);
	
	data1 = [[NSData alloc] initWithContentsOfFile:[@"/tmp" stringByAppendingPathComponent:fileName]];
	AssertNotNil(data1, nil);
	
	//Generated with 'openssl aes-256-cbc -k "info@pol-online.net" -nosalt -in Image.jpg -out Image.aes256'
	data2 = [[NSData alloc] initWithContentsOfFile:@"Resources/Image.aes256"];
	AssertNotNil(data2, nil);
	
	AssertEqualObjects(data1, data2, nil);
	
	[data2 release];
	[data1 release];
	
	AssertTrue([controller deleteFileAtPath:@"Test.jpg"], nil);
	
	[controller setEncryptionPassword:nil];
	[controller setDelegate:nil];
}

- (void) testLocal
{
	NSString*					path = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSError*					error;
	
	AssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:&error], [error localizedDescription]);
	[self _testURL:[NSURL fileURLWithPath:path]];
	AssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:&error], [error localizedDescription]);
}

- (void) testAFP
{
	NSURL*						url;
	
	for(url in [self _testURLsForProtocol:@"AFP"])
	[self _testURL:url];
}

- (void) testSMB
{
	NSURL*						url;
	
	for(url in [self _testURLsForProtocol:@"SMB"])
	[self _testURL:url];
}

- (void) testSFTP
{
	NSURL*						url;
	
	for(url in [self _testURLsForProtocol:@"SFTP"])
	[self _testURL:url];
}

- (void) testFTP
{
	NSURL*						url;
	
	//FIXME: FTP fails deleting non-existent files or directories (issue #4)
	for(url in [self _testURLsForProtocol:@"FTP"])
	[self _testURL:url];
}

- (void) testFTPS
{
	NSURL*						url;
	
	//FIXME: FTP fails deleting non-existent files or directories (issue #4)
	for(url in [self _testURLsForProtocol:@"FTPS"])
	[self _testURL:url];
}

- (void) testIDisk
{
	NSURL*						url;
	
	for(url in [self _testURLsForProtocol:@"iDisk"])
	[self _testURL:url];
}

- (void) testWebDAV
{
	NSURL*						url;
	
	for(url in [self _testURLsForProtocol:@"WebDAV"])
	[self _testURL:url];
}

- (void) testSecuredWebDAV
{
	NSURL*						url;
	
	for(url in [self _testURLsForProtocol:@"SecureWebDAV"])
	[self _testURL:url];
}

- (void) _testAmazonS3:(BOOL)secure
{
	NSString*					imagePath = @"Resources/Image.jpg";
	AmazonS3TransferController*	controller;
	NSURL*						url;
	
	for(url in [self _testURLsForProtocol:(secure ? @"SecureAmazonS3" : @"AmazonS3")]) {
		[self _testURL:url];
		
		controller = [[(secure ? [SecureAmazonS3TransferController class] : [AmazonS3TransferController class]) alloc] initWithAccessKeyID:[url user] secretAccessKey:[url passwordByReplacingPercentEscapes] bucket:nil];
		AssertNotNil([controller allBuckets], nil);
		[controller release];
		
		controller = [[(secure ? [SecureAmazonS3TransferController class] : [AmazonS3TransferController class]) alloc] initWithAccessKeyID:[url user] secretAccessKey:[url passwordByReplacingPercentEscapes] bucket:@"polkit-unit-testing"];
		AssertTrue([controller createBucket], nil);
		AssertTrue([controller createBucket], nil);
		AssertTrue([controller uploadFileFromPath:imagePath toPath:@"Test.jpg"], nil);
		AssertFalse([controller deleteBucket], nil);
		AssertTrue([controller deleteFileAtPath:@"Test.jpg"], nil);
		AssertTrue([controller deleteBucket], nil);
		AssertFalse([controller deleteBucket], nil);
		[controller release];
	}
}

- (void) testAmazonS3
{
	[self _testAmazonS3:NO];
}

- (void) testSecureAmazonS3
{
	[self _testAmazonS3:YES];
}

@end
