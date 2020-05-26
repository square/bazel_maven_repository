package kramer.integration

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.ProgramResult
import java.io.ByteArrayOutputStream

/**
 * Executes a non-terminating run (via [CliktCommand.parse]) which traps any exceptions and
 * reports them, returning the output print stream as a string for assertions.
 *
 * For expected-errors, call [CliktCommand.fail].]
 */
fun CliktCommand.test(args: List<String>, output: ByteArrayOutputStream): String {
  println("Testing with args: [\n    ${args.joinToString("\n    ")}\n]")
  try {
    parse(args)
    return output.toString()
  } catch (e: ProgramResult) {
    throw AssertionError("Program exited with unexpected code: ${e.statusCode}. output: $output")
  } catch (e: Exception) {
    throw AssertionError("Exception running command:\n $output", e)
  }
}

/**
 * Executes a non-terminating run (via [CliktCommand.parse]) asserts that the command failed
 * with a ProgramResult with a non-0 exit code, and returns the output stream, throwing an
 * [AssertionError] if the program returns without error.
 *
 * For regular no-error-expected tests, call [CliktCommand.test].]
 */
fun CliktCommand.fail(args: List<String>, output: ByteArrayOutputStream): String {
  println("Testing with args: [\n    ${args.joinToString("\n    ")}\n]")
  try {
    parse(args)
    throw AssertionError("Expected program to fail, but returned normally:\n $output")
  } catch (e: ProgramResult) {
    if (e.statusCode == 0)
      throw AssertionError("Expected program to fail, but returned a 0 exit status:\n $output")
    return output.toString()
  } catch (e: Exception) {
    throw AssertionError("Unexpected exception running command:\n $output", e)
  }
}
