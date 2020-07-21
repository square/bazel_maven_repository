package blah

import androidx.core.view.ViewCompat
import foo.Foo
import com.helpshift.HelpshiftUser
import com.helpshift.InstallConfig

fun useCore() {
  val view: ViewCompat? = null
  val foo = Foo()
  foo.toString()
  val installConfig = InstallConfig.Builder().build()
  val user = HelpshiftUser.Builder("foo", "foo@foo.com").build() // from core.jar
}
