package foo;

public class Blah {
    public void blah() {
        io.reactivex.Flowable<String> flow = io.reactivex.Flowable.just("blah");
        flow.blockingFirst().split("a");
    }
}
