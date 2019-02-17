package foo;

import com.google.auto.value.AutoValue;
import com.google.common.collect.ImmutableList;
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
    Bar bar();

    static FooComponent create() {
      return DaggerFoo_FooComponent.builder().build();
    }
  }


  @AutoValue
  static abstract class Inner {
    public abstract Foo foo();

    public static Builder builder() {
      return new AutoValue_Foo_Inner.Builder();
    }

    @AutoValue.Builder
    interface Builder {
      Builder setFoo(Foo foo);
      Inner build();
    }
  }
}
