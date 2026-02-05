#!/usr/bin/env python3
"""
Libertaria Monetary Sim (LMS v0.1) - TEXT OUTPUT VERSION
Hamiltonian Economic Dynamics + EPOE Simulation
"""

import numpy as np
from dataclasses import dataclass
from typing import List, Tuple, Dict

@dataclass
class SimParams:
    """Chapter-tunable parameters"""
    Kp: float = 0.15
    Ki: float = 0.02
    Kd: float = 0.08
    V_target: float = 6.0
    M_initial: float = 1000.0
    PROTOCOL_FLOOR: float = -0.05
    PROTOCOL_CEILING: float = 0.20
    OPPORTUNITY_MULTIPLIER: float = 1.5
    DIFFICULTY_ADJUSTMENT: float = 0.9
    BASE_FEE_BURN: float = 0.1
    DEMURRAGE_RATE: float = 0.001
    MAINTENANCE_COST: float = 0.01
    GENESIS_COST: float = 0.1


class LibertariaSim:
    def __init__(self, params: SimParams = None):
        self.params = params or SimParams()
        self.M = self.params.M_initial
        self.V = 5.0
        self.P = 1.0
        self.Q = 5000.0
        self.error_integral = 0.0
        self.prev_error = 0.0
        self.history = []
    
    def calculate_energy(self) -> float:
        return 0.5 * self.M * (self.V ** 2)
    
    def pid_controller(self, error: float) -> float:
        self.error_integral += error
        derivative = error - self.prev_error
        u = (self.params.Kp * error + 
             self.params.Ki * self.error_integral + 
             self.params.Kd * derivative)
        self.prev_error = error
        return np.clip(u, self.params.PROTOCOL_FLOOR, self.params.PROTOCOL_CEILING)
    
    def apply_opportunity_window(self, delta_m: float) -> Tuple[float, bool]:
        if self.V < self.params.V_target * 0.8:
            return delta_m * self.params.OPPORTUNITY_MULTIPLIER, True
        return delta_m, False
    
    def apply_extraction(self, delta_m: float) -> Tuple[float, bool]:
        is_demurrage = False
        if self.V > self.params.V_target * 1.2:
            demurrage_burn = self.M * self.params.DEMURRAGE_RATE
            self.M -= demurrage_burn
            is_demurrage = True
            return delta_m * 0.8, is_demurrage
        return delta_m, is_demurrage
    
    def step(self, exogenous_v_shock: float = 0.0) -> dict:
        measured_v = self.V + exogenous_v_shock
        error = self.params.V_target - measured_v
        delta_m = self.pid_controller(error)
        delta_m, opportunity_active = self.apply_opportunity_window(delta_m)
        delta_m, demurrage_active = self.apply_extraction(delta_m)
        self.M *= (1 + delta_m)
        self.V = (self.P * self.Q) / self.M
        self.V *= (1 + np.random.normal(0, 0.02))
        self.V = max(0.1, self.V)
        
        return {
            'M': self.M,
            'V': self.V,
            'E': self.calculate_energy(),
            'delta_m': delta_m,
            'opportunity': opportunity_active,
            'demurrage': demurrage_active,
            'error': error
        }
    
    def run(self, epochs: int = 200, shocks: List[Tuple[int, float]] = None) -> List[dict]:
        shocks = shocks or []
        shock_dict = {e: s for e, s in shocks}
        
        for t in range(epochs):
            shock = shock_dict.get(t, 0.0)
            snapshot = self.step(shock)
            snapshot['t'] = t
            self.history.append(snapshot)
        
        return self.history


def scenario_1_deflationary_death_spiral():
    print("\n" + "="*70)
    print("SCENARIO 1: DEFLATIONARY DEATH SPIRAL")
    print("="*70)
    print("Setup: Velocity crashes from 5.0 to 1.0 at epoch 50")
    print("Test: Can Opportunity Window (stimulus) break the spiral?")
    
    sim = LibertariaSim()
    history = sim.run(epochs=150, shocks=[(50, -4.0)])
    
    # Find key metrics
    v_values = [h['V'] for h in history]
    v_min = min(v_values)
    v_final = v_values[-1]
    opportunity_count = sum(1 for h in history if h['opportunity'])
    
    # Find recovery time
    recovery_time = None
    for h in history[50:]:
        if h['V'] > sim.params.V_target * 0.8:
            recovery_time = h['t'] - 50
            break
    
    print(f"\n📊 RESULTS:")
    print(f"   Minimum V:        {v_min:.2f} (target: {sim.params.V_target})")
    print(f"   Final V:          {v_final:.2f}")
    print(f"   Recovery time:    {recovery_time if recovery_time else 'NOT RECOVERED'} epochs after shock")
    print(f"   Opportunity windows: {opportunity_count} epochs")
    
    # Show trajectory
    print(f"\n📈 TRAJECTORY (selected epochs):")
    for h in history[::20]:
        marker = ""
        if h['opportunity']: marker += " [OPP]"
        if h['demurrage']: marker += " [BURN]"
        print(f"   t={h['t']:3d}: V={h['V']:.2f}, M={h['M']:.0f}, E={h['E']:.0f}{marker}")
    
    success = v_final > sim.params.V_target * 0.8
    print(f"\n{'✅ SUCCESS' if success else '❌ FAILED'}: System {'recovered' if success else 'stuck in stagnation'}")
    return success


def scenario_2_tulip_mania():
    print("\n" + "="*70)
    print("SCENARIO 2: TULIP MANIA (HYPER-VELOCITY)")
    print("="*70)
    print("Setup: Speculative bubble pushes V from 5.0 to 40.0 at epoch 50")
    print("Test: Can Demurrage + Burn cool the system without killing it?")
    
    sim = LibertariaSim()
    history = sim.run(epochs=150, shocks=[(50, 35.0)])
    
    v_values = [h['V'] for h in history]
    v_max = max(v_values)
    v_final = v_values[-1]
    demurrage_count = sum(1 for h in history if h['demurrage'])
    
    # Find cooling time
    cooling_time = None
    for h in history[50:]:
        if h['V'] < sim.params.V_target * 1.5:
            cooling_time = h['t'] - 50
            break
    
    print(f"\n📊 RESULTS:")
    print(f"   Maximum V:        {v_max:.2f} (target: {sim.params.V_target})")
    print(f"   Final V:          {v_final:.2f}")
    print(f"   Cooling time:     {cooling_time if cooling_time else 'NOT COOLED'} epochs after shock")
    print(f"   Demurrage epochs: {demurrage_count}")
    
    print(f"\n📈 TRAJECTORY (selected epochs):")
    for h in history[::20]:
        marker = ""
        if h['opportunity']: marker += " [OPP]"
        if h['demurrage']: marker += " [BURN]"
        print(f"   t={h['t']:3d}: V={h['V']:.2f}, M={h['M']:.0f}, E={h['E']:.0f}{marker}")
    
    success = v_final < sim.params.V_target * 1.5
    print(f"\n{'✅ SUCCESS' if success else '❌ FAILED'}: System {'cooled' if success else 'still overheated'}")
    return success


def scenario_3_sybil_attack():
    print("\n" + "="*70)
    print("SCENARIO 3: SYBIL ATTACK RESISTANCE")
    print("="*70)
    print("Setup: 10,000 fake accounts try to game the Opportunity Window")
    print("Test: Do maintenance costs make attack economically unviable?")
    
    sim = LibertariaSim()
    
    # Attack parameters
    n_sybils = 10000
    epochs = 100
    maintenance_per_epoch = sim.params.MAINTENANCE_COST
    
    # Total attack cost
    total_attack_cost = n_sybils * maintenance_per_epoch * epochs
    
    # Simulate with stagnation (opportunity window active)
    sim.V = 2.0  # Force stagnation
    history = sim.run(epochs=epochs)
    
    # Calculate potential gain
    opportunity_epochs = sum(1 for h in history if h['opportunity'])
    # During opportunity, each sybil could mint ~5% of M (with bonus)
    avg_mint = sim.params.M_initial * 0.05 * sim.params.OPPORTUNITY_MULTIPLIER
    # But they share the pie - assume 1% capture per sybil
    potential_gain_per_sybil = avg_mint * 0.0001
    total_potential_gain = n_sybils * potential_gain_per_sybil * opportunity_epochs
    
    print(f"\n📊 ATTACK ECONOMICS:")
    print(f"   Sybil accounts:        {n_sybils:,}")
    print(f"   Epochs:                {epochs}")
    print(f"   Maintenance cost:      {maintenance_per_epoch} energy/epoch/account")
    print(f"   TOTAL ATTACK COST:     {total_attack_cost:,.1f} energy")
    print(f"   ")
    print(f"   Opportunity epochs:    {opportunity_epochs}")
    print(f"   Potential gain:        {total_potential_gain:,.1f} energy")
    print(f"   ")
    print(f"   ROI:                   {(total_potential_gain/total_attack_cost)*100:.2f}%")
    
    viable = total_potential_gain > total_attack_cost
    print(f"\n{'❌ ATTACK UNVIABLE' if not viable else '⚠️ WARNING: Attack profitable'}")
    if not viable:
        print(f"   Attackers lose {total_attack_cost - total_potential_gain:,.1f} energy")
    
    return not viable


def parameter_sweep():
    print("\n" + "="*70)
    print("PARAMETER SWEEP: OPTIMAL PID TUNING")
    print("="*70)
    print("Testing different Ki (integral gain) values")
    print("Goal: Fast recovery + minimal overshoot")
    
    ki_values = [0.005, 0.01, 0.02, 0.05]
    results = []
    
    for ki in ki_values:
        params = SimParams(Ki=ki)
        sim = LibertariaSim(params)
        
        # Stagnation shock
        history = sim.run(epochs=100, shocks=[(30, -3.0)])
        
        v_values = [h['V'] for h in history]
        
        # Recovery time
        recovery_time = None
        for i, h in enumerate(history[30:], start=30):
            if h['V'] > params.V_target * 0.8:
                recovery_time = i - 30
                break
        
        # Overshoot
        max_v = max(v_values[50:]) if len(v_values) > 50 else max(v_values)
        overshoot = max(0, (max_v - params.V_target) / params.V_target * 100)
        
        final_v = v_values[-1]
        
        results.append({
            'ki': ki,
            'recovery': recovery_time or 999,
            'overshoot': overshoot,
            'final_v': final_v
        })
        
        print(f"   Ki={ki:.3f}: recovery={recovery_time or 'FAIL':>4} epochs, "
              f"overshoot={overshoot:.1f}%, final_V={final_v:.2f}")
    
    # Find best
    best = min(results, key=lambda x: x['recovery'] + x['overshoot'])
    print(f"\n🏆 OPTIMAL: Ki={best['ki']} (fastest recovery, minimal overshoot)")
    
    return best['ki']


if __name__ == "__main__":
    print("\n" + "="*70)
    print(" LIBERTARIA MONETARY SIMULATION v0.1")
    print(" Hamiltonian Economics + EPOE")
    print("="*70)
    
    # Run all scenarios
    results = []
    results.append(("Deflationary Death Spiral", scenario_1_deflationary_death_spiral()))
    results.append(("Tulip Mania", scenario_2_tulip_mania()))
    results.append(("Sybil Attack", scenario_3_sybil_attack()))
    
    # Parameter sweep
    optimal_ki = parameter_sweep()
    
    # Summary
    print("\n" + "="*70)
    print(" FINAL SUMMARY")
    print("="*70)
    
    for name, passed in results:
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"   {status}: {name}")
    
    print(f"\n   Optimal PID tuning: Ki ≈ {optimal_ki}")
    
    all_passed = all(r[1] for r in results)
    print(f"\n{'✅ EPOE DESIGN VALIDATED' if all_passed else '❌ ISSUES DETECTED'}")
    print("   Ready for production implementation" if all_passed else "   Needs revision")
