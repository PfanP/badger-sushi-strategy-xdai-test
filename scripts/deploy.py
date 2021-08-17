from brownie import *
from config import (
  BADGER_DEV_MULTISIG,
  WANT,
  LP_COMPONENT,
  REWARD_TOKEN,
  PROTECTED_TOKENS,
  FEES,
  WETH
)
from dotmap import DotMap
from helpers.constants import MaxUint256

def main():
  return deploy()

def deploy():
  """
    Deploys, vault, controller and strats and wires them up for you to test
  """
  deployer = accounts[10]

  strategist = deployer
  keeper = deployer
  guardian = deployer

  governance = accounts.at(BADGER_DEV_MULTISIG, force=True)

  controller = Controller.deploy({"from": deployer})
  controller.initialize(
    BADGER_DEV_MULTISIG,
    strategist,
    keeper,
    BADGER_DEV_MULTISIG
  )

  sett = SettV3.deploy({"from": deployer})
  sett.initialize(
    WANT,
    controller,
    BADGER_DEV_MULTISIG,
    keeper,
    guardian,
    False,
    "prefix",
    "PREFIX"
  )

  controller.setVault(WANT, sett, {'from': strategist})


  ## TODO: Add guest list once we find compatible, tested, contract
  # guestList = VipCappedGuestListWrapperUpgradeable.deploy({"from": deployer})
  # guestList.initialize(sett, {"from": deployer})
  # guestList.setGuests([deployer], [True])
  # guestList.setUserDepositCap(100000000)
  # sett.setGuestList(guestList, {"from": governance})

  ## Start up Strategy
  strategy = StrategySushiBadgerWbtc.deploy({"from": deployer})
  strategy.initialize(
    BADGER_DEV_MULTISIG,
    strategist,
    controller,
    keeper,
    guardian,
    PROTECTED_TOKENS,
    FEES
  )

  sett.unpause({"from": governance})

  ## Tool that verifies bytecode (run independetly) <- Webapp for anyone to verify

  ## Set up tokens
  want = interface.IERC20(WANT)
  weth = interface.IERC20(WETH)
  lpComponent = interface.IERC20(LP_COMPONENT)
  rewardToken = interface.IERC20(REWARD_TOKEN)
  sushi = interface.IERC20("0x2995D1317DcD4f0aB89f4AE60F3f020A4F17C7CE")
  ## Wire up Controller to Strart
  ## In testing will pass, but on live it will fail
  controller.approveStrategy(WANT, strategy, {"from": governance})
  controller.setStrategy(WANT, strategy, {"from": governance})

  ## Uniswap some tokens here
  # router = Contract.from_explorer("0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D")
  want.approve("0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", MaxUint256, {"from": deployer})
  weth.approve("0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", MaxUint256, {"from": deployer})
  
  accounts[0].transfer(deployer, 9999999999999999)

  return DotMap(
    deployer=deployer,
    controller=controller,
    vault=sett,
    sett=sett,
    strategy=strategy,
    # guestList=guestList,
    want=want,
    lpComponent=lpComponent,
    rewardToken=rewardToken,
    weth=weth,
    sushi=sushi
  )
