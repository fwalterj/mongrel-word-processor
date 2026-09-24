# Generates a CLT fallback runner from repository XCTest method bodies.
# This is a native assertion harness, not an XCTest replacement or runner.
from pathlib import Path
import re, sys
shim='''import AppKit
import Foundation
@MainActor var failures = 0
@MainActor class XCTestCase { func setUpWithError() throws {}\nfunc tearDownWithError() throws {} }
struct UnwrapFailure: Error {}
@MainActor func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) { failures += 1; print("FAIL \\(line): \\(message)") }
@MainActor func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { do { if try !value() { XCTFail("Expected true " + message, file: file, line: line) } } catch { XCTFail("Assertion threw: \(error)", file: file, line: line) } }
@MainActor func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { do { if try value() { XCTFail("Expected false " + message, file: file, line: line) } } catch { XCTFail("Assertion threw: \(error)", file: file, line: line) } }
@MainActor func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { do { let first = try a(); let second = try b(); if first != second { XCTFail("Unequal: \\(String(describing: first).prefix(200)) / \\(String(describing: second).prefix(200)) " + message, file: file, line: line) } } catch { XCTFail("Assertion threw: \(error)", file: file, line: line) } }
@MainActor func XCTAssertEqual<T: BinaryFloatingPoint>(_ a: T, _ b: T, accuracy: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { if abs(a-b) > accuracy { XCTFail("Outside tolerance \\(a) / \\(b) " + message, file: file, line: line) } }
@MainActor func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { if a == b { XCTFail("Equal values " + message, file: file, line: line) } }
@MainActor func XCTAssertNil<T>(_ a: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { if a != nil { XCTFail("Expected nil " + message, file: file, line: line) } }
@MainActor func XCTAssertNotNil<T>(_ a: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { if a == nil { XCTFail("Unexpected nil " + message, file: file, line: line) } }
@MainActor func XCTUnwrap<T>(_ a: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T { guard let a else { XCTFail("Unexpected nil " + message, file: file, line: line); throw UnwrapFailure() }; return a }
@MainActor func XCTAssertThrowsError<T>(_ a: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { do { _ = try a(); XCTFail("Expected error " + message, file: file, line: line) } catch {} }
'''
for name,op in [('GreaterThan','>'),('GreaterThanOrEqual','>='),('LessThan','<')]:
 shim+='@MainActor func XCTAssert'+name+'<T: Comparable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { if !(a '+op+' b) { XCTFail("Comparison failed \\(a) / \\(b) " + message, file: file, line: line) } }\n'
sources=[];calls=[]
for p in sorted(Path('Tests').glob('*.swift')):
 src=p.read_text().replace('import XCTest\n','').replace('@testable import MongrelWordProcessor\n','')
 cls=re.search(r'final class (\w+): XCTestCase',src)[1]
 src=re.sub(r'XCTAssertEqual\(try ', 'try XCTAssertEqual(try ', src)
 sources.append(src)
 for name in re.findall(r'    func (test\w+)\(',src):
  calls.append('do { let t = '+cls+'(); try t.setUpWithError(); defer { try? t.tearDownWithError() }; let before = failures; let start = Date(); try t.'+name+'(); print("CHECK '+cls+'.'+name+' \\(failures == before ? "PASS" : "FAIL") \\(Date().timeIntervalSince(start))s") } catch { XCTFail("'+name+': \\(error)") }')
main='\n@main struct RunAllChecks { @MainActor static func main() { _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited);\n'+'\n'.join(calls)+'\nprint("CHECKS: '+str(len(calls))+' FAILURES: \\(failures)"); exit(failures == 0 ? 0 : 1) } }'
Path(sys.argv[1]).write_text(shim+'\n'.join(sources)+main)
