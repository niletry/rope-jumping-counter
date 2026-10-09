package com.yzrun.ropecounter

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.yzrun.ropecounter.ui.AppScreen
import com.yzrun.ropecounter.ui.HistoryScreen
import com.yzrun.ropecounter.ui.RopeCounterTheme
import com.yzrun.ropecounter.ui.RopeCounterViewModel
import com.yzrun.ropecounter.ui.SetupScreen
import com.yzrun.ropecounter.ui.WorkoutScreen

class MainActivity : ComponentActivity() {
    private val viewModel: RopeCounterViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        intent?.getStringExtra("replay_dir")?.let { viewModel.setReplayDir(it) }

        setContent {
            RopeCounterTheme {
                val state by viewModel.state.collectAsState()
                when (state.screen) {
                    AppScreen.SETUP -> SetupScreen(
                        config = state.config,
                        historyCount = state.history.size,
                        onConfigChange = viewModel::updateConfig,
                        onStart = viewModel::startWorkout,
                        onHistory = viewModel::openHistory,
                    )

                    AppScreen.WORKOUT -> WorkoutScreen(
                        state = state,
                        onPoseFrame = viewModel::onPoseFrame,
                        onSwitchCamera = viewModel::switchCamera,
                        onTogglePause = viewModel::togglePause,
                        onFinish = viewModel::finishWorkout,
                        onDone = viewModel::returnToSetup,
                        onError = viewModel::showError,
                    )

                    AppScreen.HISTORY -> HistoryScreen(
                        records = state.history,
                        onBack = viewModel::returnToSetup,
                        onClear = viewModel::clearHistory,
                    )
                }

                state.errorMessage?.let { message ->
                    AlertDialog(
                        onDismissRequest = viewModel::dismissError,
                        title = { Text("提示") },
                        text = { Text(message) },
                        confirmButton = {
                            TextButton(onClick = viewModel::dismissError) { Text("知道了") }
                        },
                    )
                }
            }
        }
    }
}
