# ICT & CRT Gold Trading System for MQL5

## 📋 Vue d'ensemble

Système de trading automatisé combinant les stratégies **Inner Circle Trader (ICT)** et **Concept Refined Trading (CRT)** pour le trading de l'or (XAUUSD) sur MetaTrader 5.

## 🏗️ Architecture du Projet

```
ICT_CRT_Gold_System/
├── ICT_CRT_Gold_EA.mq5           # Expert Advisor principal
├── Include/                       # Bibliothèques de fonctions
│   ├── ICT_Functions.mqh         # Logique ICT
│   ├── CRT_Functions.mqh         # Logique CRT
│   ├── RiskManagement.mqh        # Gestion des risques
│   ├── SignalManager.mqh         # Gestion des signaux
│   └── NotificationManager.mqh   # Notifications
└── Indicators/
    └── ICT_CRT_Dashboard.mq5     # Dashboard visuel
```

## 🎯 Fonctionnalités Principales

### Stratégie ICT (Inner Circle Trader)
- ✅ **Order Blocks** - Identification des blocs d'ordres institutionnels
- ✅ **Fair Value Gaps (FVG)** - Détection des écarts de valeur équitable
- ✅ **Break of Structure (BOS)** - Cassure de structure
- ✅ **Liquidity Grabs** - Capture de liquidité
- ✅ **Market Structure** - Analyse Higher Highs/Lower Lows

### Stratégie CRT (Concept Refined Trading)
- ✅ **Supply/Demand Zones** - Zones d'offre et de demande
- ✅ **Trendline Breaks** - Cassures de lignes de tendance
- ✅ **Volume Profile** - Profil de volume (POC, HVN, LVN)
- ✅ **Consolidation Detection** - Détection des consolidations
- ✅ **Trend Analysis** - Analyse de tendance multi-critères

### Gestion des Risques
- ✅ **Auto Lot Sizing** - Calcul automatique de la taille des lots
- ✅ **Risk Percentage** - Risque en % du capital
- ✅ **Trailing Stop** - Stop suiveur configurable
- ✅ **Max Drawdown Protection** - Protection contre le drawdown excessif
- ✅ **Daily Trade Limit** - Limite de trades quotidiens

### Gestion des Signaux
- ✅ **Signal Confluence** - Combinaison intelligente des signaux ICT/CRT
- ✅ **Weighted Scoring** - Système de pondération configurable
- ✅ **Signal History** - Historique et statistiques
- ✅ **Confidence Levels** - Niveaux de confiance

### Notifications
- ✅ **Push Notifications** - Notifications mobiles
- ✅ **Email Alerts** - Alertes par email
- ✅ **Sound Alerts** - Alertes sonores
- ✅ **Trade Notifications** - Notifications d'exécution de trades

## ⚙️ Installation

### 1. Copier les fichiers
```bash
# Copier le dossier dans le répertoire MQL5
MetaTrader 5/MQL5/Experts/ICT_CRT_Gold_System/
```

### 2. Compiler dans MetaEditor
- Ouvrir MetaEditor (F4 dans MT5)
- Compiler `ICT_CRT_Gold_EA.mq5`
- Compiler `ICT_CRT_Dashboard.mq5`

### 3. Ajouter au graphique
- Ouvrir un graphique XAUUSD
- Glisser-déposer l'EA depuis le Navigateur
- Configurer les paramètres

## 📊 Configuration Recommandée

### Paramètres de Base
```
Symbol: XAUUSD (Gold)
Timeframe: H1 (Hourly)
Lot Size: 0.01 (ou Auto)
Risk Percent: 2%
Max Daily Trades: 5
```

### Paramètres ICT
```
ICT Timeframe: H1
Order Blocks: Enabled
Fair Value Gaps: Enabled
Break of Structure: Enabled
Liquidity Grab: Enabled
Lookback: 100 bars
```

### Paramètres CRT
```
CRT Timeframe: M15
Supply/Demand: Enabled
Trendlines: Enabled
Volume Profile: Enabled
Lookback: 200 bars
```

### Gestion des Risques
```
Stop Loss: 500 points
Take Profit: 1000 points
Trailing Stop: 300 points
Max Drawdown: 10%
```

## 🔍 Logique de Trading

### Signaux ICT
1. **Order Blocks** - Recherche de blocs d'ordres avant mouvements impulsifs
2. **FVG** - Identification des gaps à combler
3. **BOS** - Confirmation de changement de structure
4. **Liquidity** - Détection de sweeps de liquidité

### Signaux CRT
1. **Supply/Demand** - Zones de réaction institutionnelle
2. **Trend Analysis** - Confirmation de tendance (MA + Higher Highs/Lower Lows)
3. **Trendlines** - Support/Résistance dynamiques
4. **Volume Profile** - Zones de forte activité

### Confluence
Le système combine les signaux:
- **Score Bullish** = ICT Bullish + CRT Bullish
- **Score Bearish** = ICT Bearish + CRT Bearish
- **Threshold** = Minimum 4 points pour entrer en trade

## 📈 Dashboard

Le dashboard affiche en temps réel:
- Structure de marché (Trend, BOS)
- Signaux ICT (Order Blocks, FVG, Liquidity)
- Signaux CRT (Supply/Demand, Trendlines, Volume)
- Signal combiné final
- Informations du compte (Balance, Equity, P/L, Drawdown)

## 🛡️ Sécurité

- Vérification des heures de trading
- Filtres de jours de la semaine
- Protection contre le sur-trading
- Limite de drawdown
- Cooldown entre trades
- Validation des signaux

## 📱 Notifications

Le système envoie des alertes pour:
- Ouverture de trade
- Fermeture de trade
- Signaux détectés
- Alertes de risque
- Drawdown excessif
- Erreurs d'exécution

## 🔧 Paramètres Avancés

### Signal Weights
```cpp
ICT Weight: 0.6 (60%)
CRT Weight: 0.4 (40%)
```

### Time Filters
```cpp
Trading Hours: 08:00 - 20:00
Trading Days: Monday to Friday
```

### Confluence Requirements
```cpp
Min Confluence Score: 4
Require Both Signals: False (weighted)
```

## 📝 Notes Importantes

1. **Backtesting** - Testez d'abord sur compte démo
2. **Optimisation** - Ajustez les paramètres selon le marché
3. **VPS Recommandé** - Pour trading 24/7
4. **Spread** - Vérifiez les spreads de votre broker
5. **Slippage** - Configurez une déviation appropriée

## 🚀 Prochaines Étapes

Pour ajouter des conditions supplémentaires, envoyez les parties suivantes:
- Partie 2: Conditions additionnelles ICT
- Partie 3: Conditions additionnelles CRT
- Partie 4: Filtres et optimisations
- Partie 5: Stratégies avancées

## ⚠️ Disclaimer

Ce système est fourni à des fins éducatives. Le trading comporte des risques. Ne tradez qu'avec de l'argent que vous pouvez vous permettre de perdre.

## 📧 Support

Pour des questions ou suggestions, créez une issue dans le repository.

---

**Version:** 1.00
**Date:** 2025
**License:** MIT
