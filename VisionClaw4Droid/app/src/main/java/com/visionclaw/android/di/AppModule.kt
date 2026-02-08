package com.visionclaw.android.di

import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * Hilt dependency injection module.
 * Currently all ViewModels use @HiltViewModel with @Inject constructor()
 * so no explicit @Provides are needed. This module serves as the extension
 * point for adding singleton-scoped dependencies (e.g., shared OkHttpClient,
 * database, DAT SDK wrapper) in the future.
 */
@Module
@InstallIn(SingletonComponent::class)
object AppModule
