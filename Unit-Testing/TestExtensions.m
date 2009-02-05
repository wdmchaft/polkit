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

#import "NSData+Encryption.h"
#import "NSData+GZip.h"
#import "NSURL+Parameters.h"
#import "NSFileManager+LockedItems.h"

@interface ExtensionsTestCase : SenTestCase
@end

@implementation ExtensionsTestCase

- (void) testMD5
{
	NSMutableString*		md5String;
	NSData*					md5Data;
	NSData*					data;
	NSUInteger				i;
	NSString*				string;
	
	data = [[NSData alloc] initWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"jpg"]];
	STAssertNotNil(data, nil);
	md5Data = [data md5Digest];
	STAssertEquals([md5Data length], (NSUInteger)16, nil);
	[data release];
	
	md5String = [NSMutableString string];
	for(i = 0; i < 16; ++i)
	[md5String appendFormat:@"%02x", *((unsigned char*)[md5Data bytes] + i)];
	STAssertNotNil(md5String, nil);
	
	//Generated with 'openssl dgst -md5 Image.jpg'
	string = [NSString stringWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"md5"] encoding:NSUTF8StringEncoding error:NULL];
	STAssertEqualObjects(md5String, string, nil);
}

- (void) testSHA1
{
	NSMutableString*		sha1String;
	NSData*					sha1Data;
	NSData*					data;
	NSUInteger				i;
	NSString*				string;
	
	data = [[NSData alloc] initWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"jpg"]];
	STAssertNotNil(data, nil);
	sha1Data = [data sha1Digest];
	STAssertEquals([sha1Data length], (NSUInteger)20, nil);
	[data release];
	
	sha1String = [NSMutableString string];
	for(i = 0; i < 20; ++i)
	[sha1String appendFormat:@"%02x", *((unsigned char*)[sha1Data bytes] + i)];
	STAssertNotNil(sha1String, nil);
	
	//Generated with 'openssl dgst -sha1 Image.jpg'
	string = [NSString stringWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"sha1"] encoding:NSUTF8StringEncoding error:NULL];
	STAssertEqualObjects(sha1String, string, nil);
}

- (void) testSHA1HMac
{
	NSMutableString*		sha1String;
	NSData*					sha1Data;
	NSData*					data;
	NSUInteger				i;
	NSString*				string;
	
	data = [[NSData alloc] initWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"jpg"]];
	STAssertNotNil(data, nil);
	sha1Data = [data sha1HMacWithKey:@"info@pol-online.net"];
	STAssertEquals([sha1Data length], (NSUInteger)20, nil);
	[data release];
	
	sha1String = [NSMutableString string];
	for(i = 0; i < [sha1Data length]; ++i)
	[sha1String appendFormat:@"%02x", *((unsigned char*)[sha1Data bytes] + i)];
	STAssertNotNil(sha1String, nil);
	
	//Generated with 'openssl sha1 -hmac info@pol-online.net Image.jpg'
	string = [NSString stringWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"hmac-sha1"] encoding:NSUTF8StringEncoding error:NULL];
	STAssertEqualObjects(sha1String, string, nil);
}

- (void) testBase64
{
	NSData*					data1;
	NSData*					data2;
	NSString*				string1;
	NSString*				string2;
	NSError*				error;
	
	data1 = [[NSData alloc] initWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"jpg"]];
	STAssertNotNil(data1, nil);
	string1 = [data1 encodeBase64];
	STAssertNotNil(string1, nil);
	
	//Generated with 'openssl base64 -e -in Unit-Testing/Image.jpg -out Image.b64'
	string2 = [NSString stringWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"b64"] encoding:NSASCIIStringEncoding error:&error];
	STAssertNotNil(string2, [error localizedDescription]);
	
	STAssertEqualObjects(string1, [string2 stringByReplacingOccurrencesOfString:@"\n" withString:@""], nil);
	
	data2 = [string1 decodeBase64];
	STAssertEqualObjects(data2, data1, nil);
	
	[data1 release];
}

- (void) testBlowfish
{
	NSData*					data1;
	NSData*					data2;
	NSData*					data3;
	
	data1 = [[NSData alloc] initWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"jpg"]];
	STAssertNotNil(data1, nil);
	
	data2 = [data1 encryptBlowfishWithPassword:@"info@pol-online.net"];
	STAssertNotNil(data2, nil);
	
	//Generated with 'openssl bf-cbc -k "info@pol-online.net" -nosalt -in Image.jpg -out Image.bf'
	data3 = [NSData dataWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"bf"]];
	STAssertNotNil(data3, nil);
	
	STAssertEqualObjects(data2, data3, nil);
	
	data3 = [data2 decryptBlowfishWithPassword:@"info@pol-online.net"];
	STAssertEqualObjects(data3, data1, nil);
	
	[data1 release];
}

- (void) testAES128
{
	NSData*					data1;
	NSData*					data2;
	NSData*					data3;
	
	data1 = [[NSData alloc] initWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"jpg"]];
	STAssertNotNil(data1, nil);
	
	data2 = [data1 encryptAES128WithPassword:@"info@pol-online.net"];
	STAssertNotNil(data2, nil);
	
	//Generated with 'openssl aes-128-cbc -k "info@pol-online.net" -nosalt -in Image.jpg -out Image.aes128'
	data3 = [NSData dataWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"aes128"]];
	STAssertNotNil(data3, nil);
	
	STAssertEqualObjects(data2, data3, nil);
	
	data3 = [data2 decryptAES128WithPassword:@"info@pol-online.net"];
	STAssertEqualObjects(data3, data1, nil);
	
	[data1 release];
}

- (void) testAES256
{
	NSData*					data1;
	NSData*					data2;
	NSData*					data3;
	
	data1 = [[NSData alloc] initWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"jpg"]];
	STAssertNotNil(data1, nil);
	
	data2 = [data1 encryptAES256WithPassword:@"info@pol-online.net"];
	STAssertNotNil(data2, nil);
	
	//Generated with 'openssl aes-256-cbc -k "info@pol-online.net" -nosalt -in Image.jpg -out Image.aes256'
	data3 = [NSData dataWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"aes256"]];
	STAssertNotNil(data3, nil);
	
	STAssertEqualObjects(data2, data3, nil);
	
	data3 = [data2 decryptAES256WithPassword:@"info@pol-online.net"];
	STAssertEqualObjects(data3, data1, nil);
	
	[data1 release];
}

- (void) testGZip
{
	NSString*				path = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSData*					data1;
	NSData*					data2;
	NSError*				error;
	
	data1 = [[NSData alloc] initWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"Image" ofType:@"jpg"]];
	STAssertNotNil(data1, nil);
	STAssertTrue([data1 writeToGZipFile:path], nil);
	
	data2 = [[NSData alloc] initWithGZipFile:path];
	STAssertNotNil(data2, nil);
	STAssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:&error], [error localizedDescription]);
	STAssertEqualObjects(data1, data2, nil);
	[data2 release];
	
	data2 = [data1 compressGZip];
	STAssertEqualObjects(data1, [data2 decompressGZip], nil);
	
	[data1 release];
}

- (void) testURL
{
	NSURL*					url;
	
	url = [NSURL URLWithScheme:@"http" user:@"info@pol-online.net" password:@"%1:2@3/4?5%" host:@"www.foo.com" port:8080 path:@"/test file.html"];
	STAssertNotNil(url, nil);
	STAssertEqualObjects([url scheme], @"http", nil);
	STAssertEqualObjects([url user], @"info@pol-online.net", nil);
	STAssertEqualObjects([url passwordByReplacingPercentEscapes], @"%1:2@3/4?5%", nil);
	STAssertEqualObjects([url host], @"www.foo.com", nil);
	STAssertEquals([[url port] unsignedShortValue], (UInt16)8080, nil);
	STAssertEqualObjects([url path], @"/test file.html", nil);
	STAssertEqualObjects([url URLByDeletingUserAndPassword], [NSURL URLWithString:@"http://www.foo.com:8080/test%20file.html"], nil);
}

- (void) testLockedItems
{
	NSString*				path = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSError*				error;
	
	STAssertTrue([path writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error], [error localizedDescription]);
	STAssertFalse([manager isItemLockedAtPath:path], nil);
	STAssertTrue([manager lockItemAtPath:path error:&error], [error localizedDescription]);
	STAssertTrue([manager forceRemoveItemAtPath:path error:&error], [error localizedDescription]);
}

@end
