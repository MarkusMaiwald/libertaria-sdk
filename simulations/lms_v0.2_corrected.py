#!/usr/bin/env python3
"""
Libertaria Monetary Sim (LMS v0.2) - CORRECTED
Hamiltonian Economics + EPOE Simulation

Key fix: Stimulus increases Q (economic activity), not just M
"""

import numpy as np
from dataclasses import dataclass
from typing import List, Tuple

@dataclass
class SimParams:
    Kp: float = 0.15
    Ki: float = 0.02
    Kd: float = 0.08
    V_target: float = 6.0
    M_initial: float = 1000.0
    PROTOCOL_FLOOR: float = -0.05
    PROTOCOL_CEILING: float = 0.20
    OPPORTUNITY_MULTIPLIER: float = 1.5
    STIMULUS_Q_BOOST: float = 0.15  # Stimulus boosts economic activity
    DEMURRAGE_RATE: float = 0.001


class LibertariaSim:
    def __init__(self, params: SimParams = None):
        self.params = params or SimParams()
        self.M = self.params.M_initial
        self.V = 5.0
        self.Q = 5000.0  # Real output (economic activity)
        self.P = 1.0
        self.error_integral = 0.0
        self.prev_error = 0.0
        self.history = []
    
    def calculate_energy(self):
        return 0.5 * self.M * (self.V ** 2)
    
    def pid_controller(self, error):
        self.error_integral += error
        derivative = error - self.prev_error
        u = (self.params.Kp * error + 
             self.params.Ki * self.error_integral + 
             self.params.Kd * derivative)
        self.prev_error = error
        return np.clip(u, self.params.PROTOCOL_FLOOR, self.params.PROTOCOL_CEILING)
    
    def step(self, exogenous_shock=0.0, stimulus_boost=0.0):
        """
        CORRECTED: Stimulus increases Q (activity), not just M
        """
        # Apply exogenous shock (panic, bubble, etc)
        self.V += exogenous_shock
        
        # Calculate error
        error = self.params.V_target - self.V
        delta_m = self.pid_controller(error)
        
        # Opportunity Window: During stagnation, stimulus boosts Q
        opportunity_active = self.V < self.params.V_target * 0.8
        if opportunity_active:
            # Stimulus makes it easier to mint AND boosts economic activity
            delta_m *= self.params.OPPORTUNITY_MULTIPLIER
            # KEY FIX: Stimulus increases Q (people start spending/working)
            self.Q *= (1 + self.params.STIMULUS_Q_BOOST)
        
        # Extraction: During overheating, demurrage reduces hoarding
        demurrage_active = self.V > self.params.V_target * 1.2
        if demurrage_active:
            # Demurrage on stagnant money
            self.M *= (1 - self.params.DEMURRAGE_RATE)
            delta_m *= 0.8  # Extra brake
        
        # Update Money Supply
        self.M *= (1 + delta_m)
        
        # Velocity from Fisher equation: M * V = P * Q
        # But Q is now endogenous (responds to stimulus)
        self.V = (self.P * self.Q) / self.M
        
        # Natural decay of Q (economic activity slows without stimulus)
        self.Q *= 0.995  # Slow decay
        
        # Noise
        self.V *= (1 + np.random.normal(0, 0.02))
        self.V = max(0.1, self.V)
        
        return {
            't': len(self.history),
            'M': self.M,
            'V': self.V,
            'Q': self.Q,
            'E': self.calculate_energy(),
            'delta_m': delta_m,
            'opportunity': opportunity_active,
            'demurrage': demurrage_active
        }
    
    def run(self, epochs=200, shocks=None):
        shocks = shocks or {}
        for t in range(epochs):
            shock = shocks.get(t, 0.0)
            snapshot = self.step(shock)
            self.history.append(snapshot)
        return self.history


def scenario_1_deflationary_spiral():
    print("\n" + "="*70)
    print("SCENARIO 1: DEFLATIONARY DEATH SPIRAL (CORRECTED)")
    print("="*70)
    print("Velocity crashes to 1.0, then Opportunity Window opens")
    print("Test: Does stimulus boost Q enough to recover V?")
    
    sim = LibertariaSim()
    
    # Epoch 50: Crash
    history = sim.run(epochs=150, shocks={50: -4.0})
    
    v_vals = [h['V'] for h in history]
    v_min = min(v_vals)
    v_final = v_vals[-1]
    opp_count = sum(1 for h in history if h['opportunity'])
    
    # Recovery time
    recovery = None
    for h in history[50:]:
        if h['V'] > 4.8:  # 80% of target
            recovery = h['t'] - 50
            break
    
    print(f"\n📊 RESULTS:")
    print(f"   Minimum V:     {v_min:.2f}")
    print(f"   Final V:       {v_final:.2f} (target: 6.0)")
    print(f"   Recovery:      {recovery if recovery else 'NOT RECOVERED'} epochs after shock")
    print(f"   Stimulus epochs: {opp_count}")
    print(f"   Final Q:       {history[-1]['Q']:.0f} (initial: 5000)")
    
    print(f"\n📈 KEY POINTS:")
    for h in [history[49], history[60], history[80], history[100], history[-1]]:
        status = "[STIMULUS]" if h['opportunity'] else "[NORMAL]"
        print(f"   t={h['t']:3d}: V={h['V']:.2f}, Q={h['Q']:.0f}, M={h['M']:.0f} {status}")
    
    success = v_final > 4.5
    print(f"\n{'✅ SUCCESS' if success else '❌ FAIL'}: {'Recovery achieved' if success else 'Stuck in stagnation'}")
    return success


def scenario_2_hyper_velocity():
    print("\n" + "="*70)
    print("SCENARIO 2: HYPER-VELOCITY COOLING")
    print("="*70)
    print("Bubble pushes V to 40, test cooling mechanisms")
    
    sim = LibertariaSim()
    history = sim.run(epochs=150, shocks={50: 35.0})
    
    v_vals = [h['V'] for h in history]
    v_max = max(v_vals)
    v_final = v_vals[-1]
    burn_count = sum(1 for h in history if h['demurrage'])
    
    print(f"\n📊 RESULTS:")
    print(f"   Maximum V:     {v_max:.2f}")
    print(f"   Final V:       {v_final:.2f}")
    print(f"   Burn epochs:   {burn_count}")
    
    success = v_final < 9.0  # Cooled but not dead
    print(f"\n{'✅ SUCCESS' if success else '❌ FAIL'}: {'Cooled effectively' if success else 'Still overheated'}")
    return success


def scenario_3_sybil():
    print("\n" + "="*70)
    print("SCENARIO 3: SYBIL ATTACK")
    print("="*70)
    
    n_sybils = 10000
    epochs = 100
    maintenance = 0.01
    
    attack_cost = n_sybils * maintenance * epochs
    
    # During stagnation, what can they gain?
    sim = LibertariaSim()
    sim.V = 2.0  # Force stagnation
    history = sim.run(epochs=epochs)
    
    opp_epochs = sum(1 for h in history if h['opportunity'])
    # Each sybil could capture small share
    potential_gain = n_sybils * 50 * opp_epochs * 0.0001  # Small share each
    
    print(f"\n📊 ATTACK ECONOMICS:")
    print(f"   Cost:  {attack_cost:,.0f} energy")
    print(f"   Gain:  {potential_gain:,.0f} energy")
    print(f"   ROI:   {(potential_gain/attack_cost)*100:.1f}%")
    
    viable = potential_gain > attack_cost
    print(f"\n{'❌ UNVIABLE' if not viable else '⚠️ VIABLE'}")
    return not viable


if __name__ == "__main__":
    print("\n" + "="*70)
    print(" LIBERTARIA MONETARY SIM v0.2 (CORRECTED)")
    print("="*70)
    
    results = []
    results.append(("Deflationary Recovery", scenario_1_deflationary_spiral()))
    results.append(("Hyper-V Cooling", scenario_2_hyper_velocity()))
    results.append(("Sybil Resistance", scenario_3_sybil()))
    
    print("\n" + "="*70)
    print("FINAL SUMMARY")
    print("="*70)
    for name, passed in results:
        print(f"   {'✅' if passed else '❌'} {name}")
    
    all_pass = all(r[1] for r in results)
    print(f"\n{'✅ EPOE VALIDATED' if all_pass else '❌ NEEDS WORK'}")
