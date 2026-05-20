package com.example.wallet_app

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

class FloatingView(private val context: Context, private val onClose: () -> Unit) {

    private var windowManager: WindowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var floatingView: View
    private var params: WindowManager.LayoutParams
    
    private var rootLayout: LinearLayout
    private var bubbleContainer: LinearLayout
    private var expandedContainer: LinearLayout
    private var addTxContainer: LinearLayout

    // UI Elements Small
    private var expenseTextSmall: TextView
    private var incomeTextSmall: TextView
    private var limitTextSmall: TextView
    private var leftTextSmall: TextView

    // UI Elements Expanded
    private var expenseTextLarge: TextView
    private var incomeTextLarge: TextView
    private var limitTextLarge: TextView
    private var leftTextLarge: TextView

    // Add Tx Form
    private var nameInput: EditText
    private var amountInput: EditText
    private var isIncomeToggle = false
    private var selectedCategory = "Others"
    private var expenseBtn: Button
    private var incomeBtn: Button
    private var categoryButtons = mutableListOf<TextView>()
    private lateinit var categoryContainer: LinearLayout

    private var closeZone: TextView
    private var customTypeface: Typeface? = null
    private var isExpanded = false
    
    private var initialXPos = 20
    private var initialYPos = 150

    init {
        try {
            customTypeface = Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/Crix.ttf")
        } catch (e: Exception) {
            e.printStackTrace()
        }

        rootLayout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
        }

        bubbleContainer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            
            val shape = GradientDrawable()
            shape.shape = GradientDrawable.RECTANGLE
            shape.setColor(Color.parseColor("#09090B"))
            shape.setStroke(2, Color.parseColor("#27272A"))
            shape.cornerRadius = 30f
            background = shape
            
            setPadding(35, 25, 35, 25)
            elevation = 15f
        }

        val row1 = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        expenseTextSmall = createTextView("0(Ex.)", 14f, "#F43F5E", true)
        val slash1 = createTextView(" / ", 14f, "#555555", false)
        incomeTextSmall = createTextView("0(Inc.)", 14f, "#10B981", true)
        row1.addView(expenseTextSmall)
        row1.addView(slash1)
        row1.addView(incomeTextSmall)

        val row2 = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 5, 0, 0)
        }
        limitTextSmall = createTextView("0(Lim.)", 14f, "#FFFFFF", true)
        val slash2 = createTextView(" / ", 14f, "#555555", false)
        leftTextSmall = createTextView("0(Rem.)", 14f, "#10B981", true)
        row2.addView(limitTextSmall)
        row2.addView(slash2)
        row2.addView(leftTextSmall)

        bubbleContainer.addView(row1)
        bubbleContainer.addView(row2)

        // EXPANDED CONTAINER
        expandedContainer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            
            val shape = GradientDrawable()
            shape.shape = GradientDrawable.RECTANGLE
            shape.setColor(Color.parseColor("#09090B"))
            shape.setStroke(2, Color.parseColor("#27272A"))
            val displayMetrics = DisplayMetrics()
            windowManager.defaultDisplay.getMetrics(displayMetrics)
            layoutParams = LinearLayout.LayoutParams((displayMetrics.widthPixels * 0.85).toInt(), LinearLayout.LayoutParams.WRAP_CONTENT)

            shape.cornerRadius = 40f
            background = shape
            
            setPadding(50, 60, 50, 60)
            elevation = 20f
            visibility = View.GONE
        }

        val titleExpanded = createTextView("WALLET SUMMARY", 18f, "#FFFFFF", true).apply {
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 30)
        }
        
        fun createRowLarge(label: String, color: String): TextView {
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, 15, 0, 15)
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            }
            val lbl = createTextView(label, 16f, "#AAAAAA", false)
            val v = createTextView("0", 18f, color, true).apply {
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                gravity = Gravity.END
            }
            row.addView(lbl)
            row.addView(v)
            expandedContainer.addView(row)
            return v
        }

        expandedContainer.addView(titleExpanded)
        expenseTextLarge = createRowLarge("Today's Expense", "#F43F5E")
        limitTextLarge = createRowLarge("Daily Limit", "#FFFFFF")
        leftTextLarge = createRowLarge("Remaining", "#10B981")
        incomeTextLarge = createRowLarge("Today's Income", "#10B981")

        val btnContainer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 40, 0, 0)
        }

        val addTxBtn = createButton("Add Transaction", "#6366F1", "#FFFFFF") {
            showAddTx()
        }

        val openAppBtn = createButton("Open App", "#27272A", "#FFFFFF") {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            context.startActivity(intent)
            
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.overlay_enabled", false).commit()
            remove()
            onClose()
        }

        val closeExpBtn = createButton("Minimize", "#09090B", "#F43F5E") {
            toggleExpanded()
        }

        btnContainer.addView(addTxBtn)
        btnContainer.addView(openAppBtn)
        btnContainer.addView(closeExpBtn)
        expandedContainer.addView(btnContainer)

        // ADD TX CONTAINER
        addTxContainer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            
            val shape = GradientDrawable()
            shape.shape = GradientDrawable.RECTANGLE
            shape.setColor(Color.parseColor("#09090B"))
            shape.setStroke(2, Color.parseColor("#27272A"))
            val displayMetrics = DisplayMetrics()
            windowManager.defaultDisplay.getMetrics(displayMetrics)
            layoutParams = LinearLayout.LayoutParams((displayMetrics.widthPixels * 0.85).toInt(), LinearLayout.LayoutParams.WRAP_CONTENT)

            shape.cornerRadius = 40f
            background = shape
            
            setPadding(50, 60, 50, 60)
            elevation = 20f
            visibility = View.GONE
        }

        val newTxTitle = createTextView("New Transaction", 18f, "#FFFFFF", true).apply {
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 30)
        }

        nameInput = EditText(context).apply {
            hint = "What was this for?"
            setHintTextColor(Color.parseColor("#555555"))
            setTextColor(Color.WHITE)
            textSize = 16f
            if (customTypeface != null) typeface = customTypeface
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#18181B"))
                cornerRadius = 20f
            }
            setPadding(35, 35, 35, 35)
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, 20)
            }
        }

        amountInput = EditText(context).apply {
            hint = "₹ 0"
            setHintTextColor(Color.parseColor("#555555"))
            setTextColor(Color.WHITE)
            textSize = 24f
            inputType = android.text.InputType.TYPE_CLASS_NUMBER or android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL
            if (customTypeface != null) typeface = customTypeface
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#18181B"))
                cornerRadius = 20f
            }
            setPadding(35, 35, 35, 35)
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, 30)
            }
        }

        val toggleRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, 30)
            }
        }

        expenseBtn = Button(context).apply {
            text = "Expense"
            isAllCaps = false
            if (customTypeface != null) typeface = customTypeface
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                setMargins(0, 0, 10, 0)
            }
            setOnClickListener { setIncomeToggle(false) }
        }

        incomeBtn = Button(context).apply {
            text = "Income"
            isAllCaps = false
            if (customTypeface != null) typeface = customTypeface
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                setMargins(10, 0, 0, 0)
            }
            setOnClickListener { setIncomeToggle(true) }
        }
        
        toggleRow.addView(expenseBtn)
        toggleRow.addView(incomeBtn)

        categoryContainer = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        }
        val categoryScroll = android.widget.HorizontalScrollView(context).apply {
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, 30)
            }
            isHorizontalScrollBarEnabled = false
            addView(categoryContainer)
        }
        
        setIncomeToggle(false)

        val submitBtn = createButton("Add Transaction", "#6366F1", "#FFFFFF") {
            val n = nameInput.text.toString()
            val a = amountInput.text.toString().toDoubleOrNull() ?: 0.0
            if (n.isNotEmpty() && a > 0) {
                // Background SharedPreferences Save
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val existing = prefs.getString("flutter.pending_txs", "[]") ?: "[]"
                val cleanName = n.replace("\"", "\\\"")
                val isIncStr = if(isIncomeToggle) "true" else "false"
                val newTxStr = "{\"name\":\"$cleanName\", \"amount\":$a, \"isIncome\":$isIncStr, \"category\":\"$selectedCategory\", \"timestamp\":${System.currentTimeMillis()}}"
                val updated = if (existing.length <= 2) "[$newTxStr]" else existing.dropLast(1) + ", $newTxStr]"
                prefs.edit().putString("flutter.pending_txs", updated).commit()

                // Optimistic UI update NATIVELY
                try {
                    val currentExp = expenseTextLarge.text.toString().replace("₹", "").trim().toDoubleOrNull() ?: 0.0
                    val currentInc = incomeTextLarge.text.toString().replace("₹", "").trim().toDoubleOrNull() ?: 0.0
                    val currentLim = limitTextLarge.text.toString().replace("₹", "").trim().toDoubleOrNull() ?: 0.0
                    
                    var newExp = currentExp
                    var newInc = currentInc
                    var newLeft = 0.0
                    
                    if (isIncomeToggle) {
                        newInc += a
                    } else {
                        newExp += a
                    }
                    if (currentLim > 0) {
                        newLeft = Math.max(0.0, currentLim - newExp)
                    }
                    
                    // Format correctly without decimals if not needed
                    val fmtExp = if (newExp % 1.0 == 0.0) newExp.toInt().toString() else newExp.toString()
                    val fmtInc = if (newInc % 1.0 == 0.0) newInc.toInt().toString() else newInc.toString()
                    val fmtLim = if (currentLim % 1.0 == 0.0) currentLim.toInt().toString() else currentLim.toString()
                    val fmtLeft = if (newLeft % 1.0 == 0.0) newLeft.toInt().toString() else newLeft.toString()
                    
                    updateData("₹$fmtExp", "₹$fmtLim", "₹$fmtLeft", "₹$fmtInc")
                } catch(e: Exception) {}

                // Broadcast for foreground handling (will gracefully be ignored if in background)
                val intent = Intent("com.example.wallet_app.ADD_TX")
                intent.setPackage(context.packageName)
                intent.putExtra("name", n)
                intent.putExtra("amount", a)
                intent.putExtra("isIncome", isIncomeToggle)
                intent.putExtra("category", selectedCategory)
                context.sendBroadcast(intent)
                hideAddTx()
            }
        }

        val cancelBtn = createButton("Cancel", "#09090B", "#F43F5E") {
            hideAddTx()
        }
        
        addTxContainer.addView(newTxTitle)
        addTxContainer.addView(nameInput)
        addTxContainer.addView(amountInput)
        addTxContainer.addView(toggleRow)
        addTxContainer.addView(categoryScroll)
        addTxContainer.addView(submitBtn)
        addTxContainer.addView(cancelBtn)

        rootLayout.addView(bubbleContainer)
        rootLayout.addView(expandedContainer)
        rootLayout.addView(addTxContainer)
        floatingView = rootLayout

        val layoutFlag: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )

        params.gravity = Gravity.TOP or Gravity.START
        params.x = initialXPos
        params.y = initialYPos

        closeZone = TextView(context).apply {
            text = "✕"
            textSize = 28f
            if (customTypeface != null) typeface = customTypeface else setTypeface(null, Typeface.BOLD)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            
            val closeShape = GradientDrawable()
            closeShape.shape = GradientDrawable.OVAL
            closeShape.setColor(Color.parseColor("#09090B"))
            closeShape.setStroke(4, Color.WHITE)
            background = closeShape
            
            visibility = View.GONE
            elevation = 10f
        }

        setupDragListener()
    }

    private fun setIncomeToggle(isIncome: Boolean) {
        isIncomeToggle = isIncome
        if (isIncome) {
            incomeBtn.setTextColor(Color.parseColor("#10B981"))
            val incShape = GradientDrawable().apply {
                setColor(Color.parseColor("#1A10B981")) // tinted green
                setStroke(2, Color.parseColor("#10B981"))
                cornerRadius = 20f
            }
            incomeBtn.background = incShape
            
            expenseBtn.setTextColor(Color.parseColor("#555555"))
            val expShape = GradientDrawable().apply {
                setColor(Color.parseColor("#18181B"))
                cornerRadius = 20f
            }
            expenseBtn.background = expShape
        } else {
            expenseBtn.setTextColor(Color.parseColor("#F43F5E"))
            val expShape = GradientDrawable().apply {
                setColor(Color.parseColor("#1AF43F5E")) // tinted red 
                setStroke(2, Color.parseColor("#F43F5E"))
                cornerRadius = 20f
            }
            expenseBtn.background = expShape
            
            incomeBtn.setTextColor(Color.parseColor("#555555"))
            val incShape = GradientDrawable().apply {
                setColor(Color.parseColor("#18181B"))
                cornerRadius = 20f
            }
            incomeBtn.background = incShape
        }
        rebuildCategoryViews()
    }

    private fun rebuildCategoryViews() {
        categoryContainer.removeAllViews()
        categoryButtons.clear()
        
        val cats = if (isIncomeToggle) {
            listOf("Salary", "Freelance", "Business", "Gift", "Refund", "Others")
        } else {
            listOf("Food", "Travel", "Shopping", "Bills", "Others")
        }
        
        cats.forEach { cat ->
            val btn = TextView(context).apply {
                text = cat
                textSize = 14f
                if (customTypeface != null) typeface = customTypeface
                setPadding(35, 20, 35, 20)
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                    setMargins(0, 0, 15, 0)
                }
                setOnClickListener { 
                    selectedCategory = cat
                    updateCategoryUI()
                }
            }
            categoryButtons.add(btn)
            categoryContainer.addView(btn)
        }
        updateCategoryUI()
    }

    private fun showAddTx() {
        expandedContainer.visibility = View.GONE
        addTxContainer.visibility = View.VISIBLE
        
        // Remove FLAG_NOT_FOCUSABLE to allow keyboard
        params.flags = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
        try { windowManager.updateViewLayout(floatingView, params) } catch (e: Exception) {}
        
        nameInput.requestFocus()
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.showSoftInput(nameInput, InputMethodManager.SHOW_IMPLICIT)
    }

    private fun hideAddTx() {
        nameInput.text.clear()
        amountInput.text.clear()
        setIncomeToggle(false)
        selectedCategory = "Others"
        updateCategoryUI()
        
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.hideSoftInputFromWindow(floatingView.windowToken, 0)
        
        addTxContainer.visibility = View.GONE
        // Return to bubble view per user request
        isExpanded = false
        bubbleContainer.visibility = View.VISIBLE
        
        params.x = initialXPos
        params.y = initialYPos
        params.flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
        try { windowManager.updateViewLayout(floatingView, params) } catch (e: Exception) {}
    }

    private fun updateCategoryUI() {
        categoryButtons.forEach { btn ->
            val isSelected = btn.text.toString() == selectedCategory
            btn.setTextColor(if (isSelected) Color.WHITE else Color.parseColor("#888888"))
            val shape = GradientDrawable().apply {
                setColor(if (isSelected) Color.parseColor("#6366F1") else Color.parseColor("#18181B"))
                cornerRadius = 20f
                if (!isSelected) {
                    setStroke(2, Color.parseColor("#27272A"))
                }
            }
            btn.background = shape
        }
    }

    private fun createButton(textStr: String, bgColor: String, textColor: String, onClick: () -> Unit): Button {
        return Button(context).apply {
            text = textStr
            setTextColor(Color.parseColor(textColor))
            isAllCaps = false
            if (customTypeface != null) typeface = customTypeface
            
            val shape = GradientDrawable()
            shape.shape = GradientDrawable.RECTANGLE
            shape.setColor(Color.parseColor(bgColor))
            shape.cornerRadius = 20f
            if (bgColor == "#09090B") {
                shape.setStroke(2, Color.parseColor("#27272A"))
            }
            background = shape
            
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, 20)
            }
            
            setOnClickListener { onClick() }
        }
    }

    private fun createTextView(textValue: String, size: Float, colorCode: String, bold: Boolean): TextView {
        return TextView(context).apply {
            text = textValue
            textSize = size
            setTextColor(Color.parseColor(colorCode))
            if (customTypeface != null) {
                typeface = customTypeface
            } else if (bold) {
                setTypeface(null, Typeface.BOLD)
            }
            setPadding(2, 0, 2, 0)
        }
    }

    fun updateData(expense: String, limit: String, left: String, income: String) {
        val cleanExp = expense.replace("₹", "").trim()
        val cleanInc = income.replace("₹", "").trim()
        val cleanLim = limit.replace("₹", "").trim()
        val cleanLeft = left.replace("₹", "").trim()

        expenseTextSmall.text = "$cleanExp(Ex.)"
        incomeTextSmall.text = "$cleanInc(Inc.)"
        limitTextSmall.text = "$cleanLim(Lim.)"
        leftTextSmall.text = "$cleanLeft(Rem.)"

        expenseTextLarge.text = "₹$cleanExp"
        incomeTextLarge.text = "₹$cleanInc"
        limitTextLarge.text = "₹$cleanLim"
        leftTextLarge.text = "₹$cleanLeft"
        
        try {
            val leftVal = cleanLeft.toDouble()
            val color = if (leftVal == 0.0 && cleanLim.toDouble() > 0) "#F43F5E" else "#10B981"
            leftTextSmall.setTextColor(Color.parseColor(color))
            leftTextLarge.setTextColor(Color.parseColor(color))
        } catch (e: Exception) {}
        
        try {
            windowManager.updateViewLayout(floatingView, params)
        } catch (e: Exception) {}
    }

    private fun toggleExpanded() {
        isExpanded = !isExpanded
        val displayMetrics = DisplayMetrics()
        windowManager.defaultDisplay.getMetrics(displayMetrics)
        
        if (isExpanded) {
            initialXPos = params.x
            initialYPos = params.y
            bubbleContainer.visibility = View.GONE
            expandedContainer.visibility = View.VISIBLE
            
            params.x = (displayMetrics.widthPixels - expandedContainer.layoutParams.width) / 2
            params.y = (displayMetrics.heightPixels) / 4
        } else {
            expandedContainer.visibility = View.GONE
            bubbleContainer.visibility = View.VISIBLE
            params.x = initialXPos
            params.y = initialYPos
        }
        
        try {
            windowManager.updateViewLayout(floatingView, params)
        } catch (e: Exception) {}
    }

    fun show() {
        try {
            val closeParams = WindowManager.LayoutParams(
                160, 160, params.type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                y = 120
            }
            windowManager.addView(closeZone, closeParams)
            windowManager.addView(floatingView, params)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun remove() {
        try {
            windowManager.removeView(floatingView)
            windowManager.removeView(closeZone)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun setupDragListener() {
        floatingView.setOnTouchListener(object : View.OnTouchListener {
            private var initialX: Int = 0
            private var initialY: Int = 0
            private var initialTouchX: Float = 0f
            private var initialTouchY: Float = 0f
            private var isDragging = false

            private var closeCenterX = 0f
            private var closeCenterY = 0f

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                if (isExpanded || addTxContainer.visibility == View.VISIBLE) return false
                
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        isDragging = false

                        val displayMetrics = DisplayMetrics()
                        windowManager.defaultDisplay.getMetrics(displayMetrics)
                        closeCenterX = displayMetrics.widthPixels / 2f
                        closeCenterY = displayMetrics.heightPixels - 120f - 80f
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - initialTouchX
                        val dy = event.rawY - initialTouchY
                        
                        if (Math.abs(dx) > 10 || Math.abs(dy) > 10) {
                            if (!isDragging) {
                                isDragging = true
                                closeZone.visibility = View.VISIBLE
                            }
                        }

                        params.x = initialX + dx.toInt()
                        params.y = initialY + dy.toInt()
                        windowManager.updateViewLayout(floatingView, params)

                        val distance = Math.sqrt(Math.pow((event.rawX - closeCenterX).toDouble(), 2.0) + Math.pow((event.rawY - closeCenterY).toDouble(), 2.0))
                        val isOverCloseZone = distance < 180

                        val closeShape = closeZone.background as GradientDrawable
                        if (isOverCloseZone) {
                            closeShape.setColor(Color.parseColor("#F43F5E"))
                            closeShape.setStroke(0, Color.TRANSPARENT)
                        } else {
                            closeShape.setColor(Color.parseColor("#09090B"))
                            closeShape.setStroke(4, Color.WHITE)
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        closeZone.visibility = View.GONE
                        
                        val distance = Math.sqrt(Math.pow((event.rawX - closeCenterX).toDouble(), 2.0) + Math.pow((event.rawY - closeCenterY).toDouble(), 2.0))
                        val isOverCloseZone = distance < 180
                        
                        if (isDragging && isOverCloseZone) {
                            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                            prefs.edit().putBoolean("flutter_overlay_enabled", false).apply()
                            remove()
                            onClose()
                        } else if (!isDragging) {
                            toggleExpanded()
                        }
                        return true
                    }
                }
                return false
            }
        })
    }
}
