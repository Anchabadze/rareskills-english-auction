// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract EnglishAuction is Ownable, ReentrancyGuard {
    constructor() Ownable(msg.sender) {}

    error ShouldBeANFTOwner();
    error MinPriceShouldBeMoreThanZero();
    error DeadlineInThePast();
    error NoAuctionWithThisId();
    error BidMustBeMoreThanZero();
    error AuctionFinished();
    error BidIsTooLow();
    error AuctionIsNotCompleted();
    error HighestBidderCantWithdraw();
    error NoBidsForThisAuction();
    error OnlySellerOrOwnerCanEndAuction();
    error AuctionIsNotFinished();
    error AuctionIsAlreadyCompleted();

    struct Auction {
        address seller;
        IERC721 nft;
        uint256 nftId;
        uint256 minPrice;
        uint256 deadline;
        address highestBidder;
        uint256 highestBid;
        bool completed;
    }

    uint256 public auctionCounter = 1;
    mapping(uint256 => Auction) auctionList;
    mapping(uint256 => mapping(address => uint256)) usersBids;

    function deposit(IERC721 nft, uint256 nftId, uint256 deadline, uint256 minPrice) external {
        if (msg.sender != nft.ownerOf(nftId)) {
            revert ShouldBeANFTOwner();
        }
        if (minPrice == 0) {
            revert MinPriceShouldBeMoreThanZero();
        }
        if (deadline <= block.timestamp) {
            revert DeadlineInThePast();
        }
        nft.safeTransferFrom(msg.sender, address(this), nftId);
        auctionList[auctionCounter] = Auction({
            seller: msg.sender,
            nft: nft,
            nftId: nftId,
            minPrice: minPrice,
            deadline: deadline,
            highestBidder: address(0),
            highestBid: 0,
            completed: false
        });

        auctionCounter++;
    }

    function bid(uint256 auctionId) external payable {
        Auction storage auction = auctionList[auctionId];
        if (auction.seller == address(0)) {
            revert NoAuctionWithThisId();
        }
        if (auction.completed == true) {
            revert AuctionFinished();
        }
        if (msg.value == 0) {
            revert BidMustBeMoreThanZero();
        }

        uint256 currentUserBid = usersBids[auctionId][msg.sender];
        uint256 newUserBid = currentUserBid + msg.value;

        if (auction.highestBid >= newUserBid) {
            revert BidIsTooLow();
        }
        auction.highestBid = newUserBid;
        auction.highestBidder = msg.sender;
        usersBids[auctionId][msg.sender] += msg.value;
    }

    function withdraw(uint256 auctionId) external nonReentrant {
        Auction storage auction = auctionList[auctionId];
        if (auction.seller == address(0)) {
            revert NoAuctionWithThisId();
        }
        if (auction.highestBidder == msg.sender) {
            revert HighestBidderCantWithdraw();
        }
        uint256 amount = usersBids[auctionId][msg.sender];
        if (amount == 0) {
            revert NoBidsForThisAuction();
        }
        delete usersBids[auctionId][msg.sender];
        (bool sent,) = payable(msg.sender).call{value: amount}("");
        require(sent, "transfer failed");
    }

    function endAuction(uint256 auctionId) external {
        Auction storage auction = auctionList[auctionId];
        if (auction.seller == address(0)) {
            revert NoAuctionWithThisId();
        }
        if (auction.deadline > block.timestamp) {
            revert AuctionIsNotFinished();
        }
        bool completed = auction.completed;
        if (completed) {
            revert AuctionIsAlreadyCompleted();
        }
        address seller = auction.seller;
        if (msg.sender != owner() && msg.sender != seller) {
            revert OnlySellerOrOwnerCanEndAuction();
        }

        uint256 amount = auction.highestBid;
        uint256 minPrice = auction.minPrice;
        IERC721 nft = auction.nft;
        uint256 nftId = auction.nftId;
        address highestBidder = auction.highestBidder;

        auction.completed = true;
        delete usersBids[auctionId][highestBidder];

        if (amount < minPrice) {
            (bool sent,) = payable(highestBidder).call{value: amount}("");
            require(sent, "transfer failed");
            nft.safeTransferFrom(address(this), seller, nftId);
        } else {
            (bool sent,) = payable(seller).call{value: amount}("");
            require(sent, "transfer failed");
            nft.safeTransferFrom(address(this), highestBidder, nftId);
        }
    }

    receive() external payable {}

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        pure
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}
