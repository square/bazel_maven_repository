package blah

import androidx.core.view.ViewCompat
import foo.Foo
import com.helpshift.InstallConfig

fun useCore() {
  val installConfig = InstallConfig.Builder().build()
  val view: ViewCompat? = null
  val foo = Foo()
  foo.toString()
}
