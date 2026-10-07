package de.lf10.selfimprovement

import android.app.Activity
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * The privacy explanation Health Connect shows a link to in its permission dialog (the intent
 * `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE`, and on Android 14 and newer the alias for
 * `android.intent.action.VIEW_PERMISSION_USAGE`, see the manifest). It is plain text without any
 * logic: what the app reads from Health Connect and what it does not do with it.
 */
class HealthRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = getString(R.string.health_rationale_title)
        val padding = (24 * resources.displayMetrics.density).toInt()
        val text =
            TextView(this).apply {
                setText(R.string.health_rationale_text)
                textSize = 16f
            }
        val close =
            Button(this).apply {
                setText(android.R.string.ok)
                setOnClickListener { finish() }
            }
        val column =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(padding, padding, padding, padding)
                addView(
                    text,
                    LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                    ),
                )
                addView(
                    close,
                    LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                    ),
                )
            }
        setContentView(ScrollView(this).apply { addView(column) })
    }
}
