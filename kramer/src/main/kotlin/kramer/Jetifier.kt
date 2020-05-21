/*
 * Copyright (C) 2020 Square, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License. You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software distributed under the License
 * is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
 * or implied. See the License for the specific language governing permissions and limitations under
 * the License.
 *
 */
package kramer

import com.squareup.tools.maven.resolution.Artifact

// Based on https://developer.android.com/jetpack/androidx/migrate/artifact-mappings
val JETIFIER_ARTIFACT_MAPPING = mapOf(
  "android.arch.core:common" to "androidx.arch.core:core-common",
  "android.arch.core:core" to "androidx.arch.core:core",
  "android.arch.core:core-testing" to "androidx.arch.core:core-testing",
  "android.arch.core:runtime" to "androidx.arch.core:core-runtime",
  "android.arch.lifecycle:common" to "androidx.lifecycle:lifecycle-common",
  "android.arch.lifecycle:common-java8" to "androidx.lifecycle:lifecycle-common-java8",
  "android.arch.lifecycle:compiler" to "androidx.lifecycle:lifecycle-compiler",
  "android.arch.lifecycle:extensions" to "androidx.lifecycle:lifecycle-extensions",
  "android.arch.lifecycle:livedata" to "androidx.lifecycle:lifecycle-livedata",
  "android.arch.lifecycle:livedata-core" to "androidx.lifecycle:lifecycle-livedata-core",
  "android.arch.lifecycle:reactivestreams" to "androidx.lifecycle:lifecycle-reactivestreams",
  "android.arch.lifecycle:runtime" to "androidx.lifecycle:lifecycle-runtime",
  "android.arch.lifecycle:viewmodel" to "androidx.lifecycle:lifecycle-viewmodel",
  "android.arch.paging:common" to "androidx.paging:paging-common",
  "android.arch.paging:runtime" to "androidx.paging:paging-runtime",
  "android.arch.paging:rxjava2" to "androidx.paging:paging-rxjava2",
  "android.arch.persistence.room:common" to "androidx.room:room-common",
  "android.arch.persistence.room:compiler" to "androidx.room:room-compiler",
  "android.arch.persistence.room:guava" to "androidx.room:room-guava",
  "android.arch.persistence.room:migration" to "androidx.room:room-migration",
  "android.arch.persistence.room:runtime" to "androidx.room:room-runtime",
  "android.arch.persistence.room:rxjava2" to "androidx.room:room-rxjava2",
  "android.arch.persistence.room:testing" to "androidx.room:room-testing",
  "android.arch.persistence:db" to "androidx.sqlite:sqlite",
  "android.arch.persistence:db-framework" to "androidx.sqlite:sqlite-framework",
  "com.android.support.constraint:constraint-layout" to
    "androidx.constraintlayout:constraintlayout",
  "com.android.support.constraint:constraint-layout-solver" to
    "androidx.constraintlayout:constraintlayout-solver",
  "com.android.support.test.espresso.idling:idling-concurrent" to
    "androidx.test.espresso.idling:idling-concurrent",
  "com.android.support.test.espresso.idling:idling-net" to
    "androidx.test.espresso.idling:idling-net",
  "com.android.support.test.espresso:espresso-accessibility" to
    "androidx.test.espresso:espresso-accessibility",
  "com.android.support.test.espresso:espresso-contrib" to "androidx.test.espresso:espresso-contrib",
  "com.android.support.test.espresso:espresso-core" to "androidx.test.espresso:espresso-core",
  "com.android.support.test.espresso:espresso-idling-resource" to
    "androidx.test.espresso:espresso-idling-resource",
  "com.android.support.test.espresso:espresso-intents" to "androidx.test.espresso:espresso-intents",
  "com.android.support.test.espresso:espresso-remote" to "androidx.test.espresso:espresso-remote",
  "com.android.support.test.espresso:espresso-web" to "androidx.test.espresso:espresso-web",
  "com.android.support.test.janktesthelper:janktesthelper" to "androidx.test.jank:janktesthelper",
  "com.android.support.test.services:test-services" to "androidx.test:test-services",
  "com.android.support.test.uiautomator:uiautomator" to "androidx.test.uiautomator:uiautomator",
  "com.android.support.test:monitor" to "androidx.test:monitor",
  "com.android.support.test:orchestrator" to "androidx.test:orchestrator",
  "com.android.support.test:rules" to "androidx.test:rules",
  "com.android.support.test:runner" to "androidx.test:runner",
  "com.android.support:animated-vector-drawable" to
    "androidx.vectordrawable:vectordrawable-animated",
  "com.android.support:appcompat-v7" to "androidx.appcompat:appcompat",
  "com.android.support:asynclayoutinflater" to "androidx.asynclayoutinflater:asynclayoutinflater",
  "com.android.support:car" to "androidx.car:car",
  "com.android.support:cardview-v7" to "androidx.cardview:cardview",
  "com.android.support:collections" to "androidx.collection:collection",
  "com.android.support:coordinatorlayout" to "androidx.coordinatorlayout:coordinatorlayout",
  "com.android.support:cursoradapter" to "androidx.cursoradapter:cursoradapter",
  "com.android.support:customtabs" to "androidx.browser:browser",
  "com.android.support:customview" to "androidx.customview:customview",
  "com.android.support:design" to "com.google.android.material:material",
  "com.android.support:documentfile" to "androidx.documentfile:documentfile",
  "com.android.support:drawerlayout" to "androidx.drawerlayout:drawerlayout",
  "com.android.support:exifinterface" to "androidx.exifinterface:exifinterface",
  "com.android.support:gridlayout-v7" to "androidx.gridlayout:gridlayout",
  "com.android.support:heifwriter" to "androidx.heifwriter:heifwriter",
  "com.android.support:interpolator" to "androidx.interpolator:interpolator",
  "com.android.support:leanback-v17" to "androidx.leanback:leanback",
  "com.android.support:loader" to "androidx.loader:loader",
  "com.android.support:localbroadcastmanager" to
    "androidx.localbroadcastmanager:localbroadcastmanager",
  "com.android.support:media2" to "androidx.media2:media2",
  "com.android.support:media2-exoplayer" to "androidx.media2:media2-exoplayer",
  "com.android.support:mediarouter-v7" to "androidx.mediarouter:mediarouter",
  "com.android.support:multidex" to "androidx.multidex:multidex",
  "com.android.support:multidex-instrumentation" to "androidx.multidex:multidex-instrumentation",
  "com.android.support:palette-v7" to "androidx.palette:palette",
  "com.android.support:percent" to "androidx.percentlayout:percentlayout",
  "com.android.support:preference-leanback-v17" to "androidx.leanback:leanback-preference",
  "com.android.support:preference-v14" to "androidx.legacy:legacy-preference-v14",
  "com.android.support:preference-v7" to "androidx.preference:preference",
  "com.android.support:print" to "androidx.print:print",
  "com.android.support:recommendation" to "androidx.recommendation:recommendation",
  "com.android.support:recyclerview-selection" to "androidx.recyclerview:recyclerview-selection",
  "com.android.support:recyclerview-v7" to "androidx.recyclerview:recyclerview",
  "com.android.support:slices-builders" to "androidx.slice:slice-builders",
  "com.android.support:slices-core" to "androidx.slice:slice-core",
  "com.android.support:slices-view" to "androidx.slice:slice-view",
  "com.android.support:slidingpanelayout" to "androidx.slidingpanelayout:slidingpanelayout",
  "com.android.support:support-annotations" to "androidx.annotation:annotation",
  "com.android.support:support-compat" to "androidx.core:core",
  "com.android.support:support-content" to "androidx.contentpager:contentpager",
  "com.android.support:support-core-ui" to "androidx.legacy:legacy-support-core-ui",
  "com.android.support:support-core-utils" to "androidx.legacy:legacy-support-core-utils",
  "com.android.support:support-dynamic-animation" to "androidx.dynamicanimation:dynamicanimation",
  "com.android.support:support-emoji" to "androidx.emoji:emoji",
  "com.android.support:support-emoji-appcompat" to "androidx.emoji:emoji-appcompat",
  "com.android.support:support-emoji-bundled" to "androidx.emoji:emoji-bundled",
  "com.android.support:support-fragment" to "androidx.fragment:fragment",
  "com.android.support:support-media-compat" to "androidx.media:media",
  "com.android.support:support-tv-provider" to "androidx.tvprovider:tvprovider",
  "com.android.support:support-v13" to "androidx.legacy:legacy-support-v13",
  "com.android.support:support-v4" to "androidx.legacy:legacy-support-v4",
  "com.android.support:support-vector-drawable" to "androidx.vectordrawable:vectordrawable",
  "com.android.support:swiperefreshlayout" to "androidx.swiperefreshlayout:swiperefreshlayout",
  "com.android.support:textclassifier" to "androidx.textclassifier:textclassifier",
  "com.android.support:transition" to "androidx.transition:transition",
  "com.android.support:versionedparcelable" to "androidx.versionedparcelable:versionedparcelable",
  "com.android.support:viewpager" to "androidx.viewpager:viewpager",
  "com.android.support:wear" to "androidx.wear:wear",
  "com.android.support:webkit" to "androidx.webkit:webkit"
)

fun String.toGlobMatcher() =
  replace(".", "[.]").replace("*", ".*").toRegex()

class ArtifactExclusionGlob(private val glob: String) {
  init {
    require(glob != "*:*") {
      "Invalid exclusion glob \"*:*\" would exclude all artifacts. Set use_jetifier=False instead."
    }
    require(glob.contains(":")) {
      "Invalid exclusion glob \"abcdef*g\" lacks the groupId:artifactId structure."
    }
    val remainder = glob.replace("*", "")
      .replace(":", "")
      .replace(".", "")
      .trim()
    require(remainder.isNotBlank()) {
      "Invalid exclusion glob \"$glob\" - requires some valid partial group or artifact id"
    }
  }
  private val parts by lazy { glob.split(":") }
  private val groupIdMatcher by lazy { parts[0].toGlobMatcher() }
  private val artifactIdMatcher by lazy { parts[1].toGlobMatcher() }

  fun matches(groupId: String, artifactId: String) =
    groupIdMatcher.matches(groupId) && artifactIdMatcher.matches(artifactId)
}

class JetifierMatcher(val matchers: List<ArtifactExclusionGlob>) {
  fun matches(artifact: Artifact): Boolean {
    matchers.forEach {
      if (it.matches(artifact.groupId, artifact.artifactId)) return true
    }
    return false
  }
}
