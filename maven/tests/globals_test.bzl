load(":testing.bzl", "asserts", "test_suite")
load("//maven:artifacts.bzl", "artifacts")
load("//maven:globals.bzl", "fetch_repo")


_artifact = artifacts.parse_spec("a.b:c:1.0")
_parent = artifacts.parse_spec("a:c-d:1.0")

def fetch_repo_pom_path_test(env):
    asserts.equals(env, "a/b/c/1.0/c-1.0.pom", fetch_repo.pom_path(_artifact))
    asserts.equals(env, "a/c-d/1.0/c-d-1.0.pom", fetch_repo.pom_path(_parent))

def fetch_repo_pom_repo_name_test(env):
    asserts.equals(env, "maven_fetch__a_b__c__pom", fetch_repo.pom_repo_name(_artifact))
    asserts.equals(env, "maven_fetch__a__c_d__pom", fetch_repo.pom_repo_name(_parent))

def fetch_repo_pom_target_test(env):
    asserts.equals(env, Label("@maven_fetch__a_b__c__pom//maven:a/b/c/1.0/c-1.0.pom"), fetch_repo.pom_target(_artifact))
    asserts.equals(env, Label("@maven_fetch__a__c_d__pom//maven:a/c-d/1.0/c-d-1.0.pom"), fetch_repo.pom_target(_parent))

def fetch_pom_target_relative_to_test(env):
    asserts.equals(
        env,
        expected = Label("@maven_fetch__a__c_d__pom//maven:a/b/c/1.0/c-1.0.pom"),
        actual = fetch_repo.pom_target_relative_to(_artifact, fetch_repo.pom_repo_name(_parent))
    )

def differentiate_ambiguous_repo_names_test(env):
    similarA = artifacts.parse_spec("foo:bar-baz:1.0")
    similarB = artifacts.parse_spec("foo.bar:baz:1.0")
    asserts.false(env, fetch_repo.pom_repo_name(similarA) == fetch_repo.pom_repo_name(similarB))
    asserts.false(env, fetch_repo.pom_path(similarA) == fetch_repo.pom_path(similarB))

def fetch_repo_artifact_path_test(env):
    asserts.equals(env, "a/b/c/1.0/c-1.0.jar", fetch_repo.artifact_path(_artifact, "jar"))
    asserts.equals(env, "a/b/c/1.0/c-1.0.aar", fetch_repo.artifact_path(_artifact, "aar"))

def fetch_repo_artifact_repo_name_test(env):
    asserts.equals(env, "maven_fetch__a_b__c", fetch_repo.artifact_repo_name(_artifact))
    asserts.equals(env, "maven_fetch__a__c_d", fetch_repo.artifact_repo_name(_parent))

def fetch_repo_artifact_target_test(env):
    asserts.equals(
        env,
        expected = Label("@maven_fetch__a_b__c//maven:a/b/c/1.0/c-1.0.jar"),
        actual = fetch_repo.artifact_target(_artifact, "jar")
    )
    asserts.equals(
        env,
        expected = Label("@maven_fetch__a_b__c//maven:a/b/c/1.0/c-1.0.aar"),
        actual = fetch_repo.artifact_target(_artifact, "aar")
    )

TESTS = [
    fetch_repo_pom_path_test,
    fetch_repo_pom_repo_name_test,
    fetch_repo_pom_target_test,
    fetch_pom_target_relative_to_test,
    differentiate_ambiguous_repo_names_test,
    fetch_repo_artifact_path_test,
    fetch_repo_artifact_repo_name_test,
    fetch_repo_artifact_target_test,
]

# Roll-up function.
def suite():
    return test_suite("globals", tests = TESTS)
