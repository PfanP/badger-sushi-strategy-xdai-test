from brownie import *
from helpers.constants import MaxUint256


def test_are_you_trying(deployer, sett, strategy, want, sushi):
  """
    Verifies that you set up the Strategy properly
  """
  # Setup
  startingBalance = want.balanceOf(deployer) // 10
  depositAmount = startingBalance // 2
  assert startingBalance >= depositAmount
  assert startingBalance >= 0
  # End Setup

  # Deposit
  assert want.balanceOf(sett) == 0

  want.approve(sett, MaxUint256, {"from": deployer})
  sett.deposit(depositAmount, {"from": deployer})

  available = sett.available()
  assert available > 0 

  sett.earn({"from": deployer})

  chain.mine(100) # Mine so we get some interest
  ## TEST 1: Does the want get used in any way?
  assert want.balanceOf(sett) == depositAmount - available
  # Did the strategy do something with the asset?
  assert want.balanceOf(strategy) < available

  # Use this if it should invest all
  assert want.balanceOf(strategy) == 0

  # Change to this if the strat is supposed to hodl and do nothing
  #assert strategy.balanceOf(want) = depositAmount
  chain.mine(100) # Mine so we get some interest

  ## TEST 2: Is the Harvest profitable?
  harvest = strategy.harvest.call({"from": deployer})
  harvestTx = strategy.harvest({"from": deployer})
  event = harvestTx.events["Harvest"][1]

  
  print(sushi.balanceOf(strategy.address))  
  # If it doesn't print, we don't want it
  assert event["harvested"] > 0


  
