#import <XCTest/XCTest.h>
#import "FLTIntegrationTestRunner.h"

@interface ResourceIntegrationTests : XCTestCase
@end

@implementation ResourceIntegrationTests

- (void)testDartIntegration {
  __block NSUInteger completed = 0;
  [[[FLTIntegrationTestRunner alloc] init]
      testIntegrationTestWithResults:^(SEL selector, BOOL success, NSString *message) {
        completed++;
        NSLog(@"Dart integration %@: %@", NSStringFromSelector(selector), success ? @"passed" : @"failed");
        XCTAssertTrue(success, @"%@: %@", NSStringFromSelector(selector), message);
      }];
  XCTAssertGreaterThan(completed, 0u, @"No Dart integration tests reported results");
}

@end
