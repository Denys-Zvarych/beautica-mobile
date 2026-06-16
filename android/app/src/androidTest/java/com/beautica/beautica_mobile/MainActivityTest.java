// Phase 17.5 — patrol native test runner entrypoint.
//
// This is the JUnit instrumentation bridge between the Android test runner
// (PatrolJUnitRunner) and the Dart patrolTest(...) cases under
// integration_test/patrol/. It is NOT a hand-written test: patrol enumerates
// the Dart tests at runtime (listDartTests) and parameterizes one JUnit case
// per Dart test, then runs each via runDartTest.
//
// It MUST live in the app's own package (com.beautica.beautica_mobile) so the
// bare `MainActivity.class` reference below resolves to
// com.beautica.beautica_mobile.MainActivity (the real FlutterActivity).
//
// Do not edit unless the patrol package changes its required runner contract —
// this file is transcribed verbatim from the patrol getting-started Android
// (Kotlin DSL) setup for patrol 4.6.x.

package com.beautica.beautica_mobile;

import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.junit.runners.Parameterized;
import org.junit.runners.Parameterized.Parameters;
import pl.leancode.patrol.PatrolJUnitRunner;

@RunWith(Parameterized.class)
public class MainActivityTest {
    @Parameters(name = "{0}")
    public static Object[] testCases() {
        PatrolJUnitRunner instrumentation =
                (PatrolJUnitRunner) InstrumentationRegistry.getInstrumentation();
        instrumentation.setUp(MainActivity.class);
        instrumentation.waitForPatrolAppService();
        return instrumentation.listDartTests();
    }

    public MainActivityTest(String dartTestName) {
        this.dartTestName = dartTestName;
    }

    private final String dartTestName;

    @Test
    public void runDartTest() {
        PatrolJUnitRunner instrumentation =
                (PatrolJUnitRunner) InstrumentationRegistry.getInstrumentation();
        instrumentation.runDartTest(dartTestName);
    }
}
