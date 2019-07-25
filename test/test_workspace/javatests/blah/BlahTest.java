package blah;

import org.junit.Test;

import static com.google.common.truth.Truth.assertThat;

public class BlahTest {
    @Test public void testBlah() {
        // Force loading of Blah.
        assertThat(new Blah()).isInstanceOf(Blah.class);
    }
}
