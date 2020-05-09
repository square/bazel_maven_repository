package foo;

import foo.Foo.FooComponent;
import org.junit.Test;

import static com.google.common.truth.Truth.assertThat;

public class FooTest {
  @Test public void testFoo() {
    Foo foo = new Foo();
    FooComponent fooComponent = FooComponent.create();
    fooComponent.bar();

    Foo.Inner inner = Foo.Inner.builder().setFoo(foo).build();
    assertThat(inner.foo()).isSameAs(foo);
  }

}
