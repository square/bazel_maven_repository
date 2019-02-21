package foo

import org.junit.Test
import java.lang.UnsupportedOperationException
import kotlin.test.assertFailsWith

class BarTest {
    @Test fun `test an inline function`() {
        assertFailsWith<UnsupportedOperationException>("didn't fail") {
            throw UnsupportedOperationException()
        }
    }
}