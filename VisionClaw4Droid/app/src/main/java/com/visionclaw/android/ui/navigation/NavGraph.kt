package com.visionclaw.android.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.visionclaw.android.ui.screens.HomeScreen
import com.visionclaw.android.ui.screens.StreamSessionScreen
import com.visionclaw.android.viewmodel.WearablesViewModel

object Routes {
    const val HOME = "home"
    const val STREAM_SESSION = "stream_session"
}

@Composable
fun NavGraph() {
    val navController = rememberNavController()
    val wearablesVM: WearablesViewModel = hiltViewModel()
    val registrationState by wearablesVM.registrationState.collectAsState()

    // Auto-navigate based on registration state (mirrors iOS MainAppView logic)
    val startDest = if (registrationState == WearablesViewModel.RegState.REGISTERED) {
        Routes.STREAM_SESSION
    } else {
        Routes.HOME
    }

    NavHost(navController = navController, startDestination = startDest) {
        composable(Routes.HOME) {
            HomeScreen(
                wearablesVM = wearablesVM,
                onRegistered = {
                    navController.navigate(Routes.STREAM_SESSION) {
                        popUpTo(Routes.HOME) { inclusive = true }
                    }
                },
            )
        }
        composable(Routes.STREAM_SESSION) {
            StreamSessionScreen(
                wearablesVM = wearablesVM,
                onDisconnected = {
                    navController.navigate(Routes.HOME) {
                        popUpTo(Routes.STREAM_SESSION) { inclusive = true }
                    }
                },
            )
        }
    }
}
