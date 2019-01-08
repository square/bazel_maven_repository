package foo;

import com.google.common.collect.ImmutableList;
import java.util.List;
import javax.inject.Inject;

public class Foo {
  final ImmutableList<String> strings = ImmutableList.of();

  @Inject public Foo() {}

  // Visible for testing
  Foo(Iterable<String> strings) {
    strings = ImmutableList.copyOf(strings);
  }

  @Override
  public boolean equals(Object o) {
    return o instanceof Foo && this.strings.equals(((Foo) o).strings);
  }

  @dagger.Component
  interface FooComponent {
    Foo foo();

    static FooComponent create() {
      return DaggerFoo_FooComponent.builder().build();
    }
  }
}
