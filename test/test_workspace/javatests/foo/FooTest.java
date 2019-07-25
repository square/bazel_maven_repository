package foo;

import foo.Foo.FooComponent;
import org.junit.Test;

public class FooTest {
  @Test public void testFoo() {
    Foo foo = new Foo();
    FooComponent fooComponent = FooComponent.create();
    fooComponent.bar();

    // Force building the dagger component.
    Foo.Inner.builder().setFoo(foo).build();
  }
}
