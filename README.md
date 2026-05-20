<div align="center">
  <img src="assets/app_icon.png" alt="CRIX Logo" width="150"/>
  
  # CRIX: Your Intelligent AI Wallet App 🚀
  
  CRIX is a next-generation personal finance and wallet application built with Flutter. It goes beyond simple expense tracking by integrating a highly intelligent AI assistant—**Crixy**—that helps you manage your money, analyze your spending habits, and handle transactions using natural language.
</div>

---

## ✨ Features & Highlights

### 🤖 Meet Crixy: Your AI Financial Assistant
At the heart of CRIX is **Crixy**, a conversational AI assistant. 
- **Natural Language Transactions**: Just say, *"Add a transaction for Shyam for eating burger for 100 Rs"*, and Crixy intelligently extracts the title, amount, and infers the category (e.g., Food).
- **Personalized Financial Insights**: Ask Crixy about your spending ("Where did I spend the most this month?"). Crixy analyzes your actual data to provide actionable advice on cutting costs and saving more.
- **Proactive Budgeting**: Crixy monitors your spending against limits, warning you if you're over-budget or if your expense-to-income ratio is unhealthy.
- **Voice Interactions**: Immersive experience with voice greetings and transitions.

### 🌟 Seamless UI/UX & Floating Assistant
- **Global Floating Window**: The `CrixyFloatingButton` is available globally across the app. A smooth Lottie-animated button lets you summon your AI assistant from anywhere with a single tap.
- **Immersive Design**: Built with custom typography (`Qarume`, `Pixel`) and beautiful Lottie animations for splash screens and interactions.
- **Data Visualization**: Interactive and responsive charts for an at-a-glance view of your financial health.

### ⚡ Tech Stack & Architecture
- **Frontend**: Flutter (Dart)
- **Local Storage**: Hive (Blazing fast NoSQL local database)
- **Backend & Cloud**: Firebase (Authentication, Cloud Firestore)
- **AI Integration**: OpenRouter API for LLM capabilities (with fallback mechanisms)

---

## 📥 Download the App

You can try out the latest version of CRIX on your Android device!
Download the **[Latest Debug APK](app-debug.apk)** right from this repository.

---

## 🛠️ Getting Started for Developers

If you want to run this project locally:

1. **Clone the repository:**
   ```bash
   git clone https://github.com/shyamdasb240299cs-wq/CRIX.git
   ```
2. **Install Dependencies:**
   ```bash
   flutter pub get
   ```
3. **Setup Environment Variables:**
   Create a `.env` file in the root directory and add your keys:
   ```env
   OPENROUTER_API_KEY=your_api_key_here
   OPENROUTER_MODEL=openai/gpt-4o-mini
   ```
4. **Run the App:**
   ```bash
   flutter run
   ```

---

*Built with ❤️ to make personal finance smart, simple, and conversational.*
