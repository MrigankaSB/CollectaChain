// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CollectaChain
 * @dev Decentralized Digital Collectibles Platform with ERC-721 implementation
 * @notice This contract enables creation, collection, and trading of unique digital assets
 */

contract Project {
    // Collectibles metadata
    string public name = "CollectaChain";
    string public symbol = "CLCT";
    
    // Counters
    uint256 private _tokenIdCounter;
    uint256 private _collectionIdCounter;
    
    // Contract owner
    address public owner;
    
    // Platform fee (in basis points, 200 = 2%)
    uint256 public platformFee = 200;
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    // Creator royalty (600 = 6%)
    uint256 public creatorRoyalty = 600;
    
    // Reentrancy guard
    bool private locked;
    
    // Rarity levels
    enum Rarity { Common, Rare, Epic, Legendary }
    
    // ERC-721 core mappings
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    
    // Collectible data
    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => address) private _creators;
    mapping(uint256 => Rarity) private _rarities;
    mapping(uint256 => uint256) private _collectionIds;
    
    // Trading system
    mapping(uint256 => uint256) private _prices;
    mapping(uint256 => bool) private _listedForSale;
    
    // Collection system
    struct Collection {
        uint256 collectionId;
        string collectionName;
        address creator;
        uint256[] tokenIds;
        uint256 totalSupply;
        bool active;
    }
    
    mapping(uint256 => Collection) public collections;
    mapping(address => uint256[]) private _creatorCollections;
    mapping(address => uint256[]) private _userCollectibles;
    
    // Events
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event CollectibleMinted(address indexed creator, uint256 indexed tokenId, Rarity rarity);
    event CollectionCreated(uint256 indexed collectionId, string name, address indexed creator);
    event CollectibleListed(uint256 indexed tokenId, uint256 price);
    event CollectibleSold(uint256 indexed tokenId, address indexed buyer, address indexed seller, uint256 price);
    event RoyaltyPaid(uint256 indexed tokenId, address indexed creator, uint256 amount);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not contract owner");
        _;
    }
    
    modifier nonReentrant() {
        require(!locked, "Reentrancy detected");
        locked = true;
        _;
        locked = false;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    // ERC-721 Core Functions
    
    function balanceOf(address tokenOwner) public view returns (uint256) {
        require(tokenOwner != address(0), "Zero address query");
        return _balances[tokenOwner];
    }
    
    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        require(tokenOwner != address(0), "Collectible does not exist");
        return tokenOwner;
    }
    
    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(_owners[tokenId] != address(0), "Collectible does not exist");
        return _tokenURIs[tokenId];
    }
    
    function approve(address to, uint256 tokenId) public {
        address tokenOwner = ownerOf(tokenId);
        require(msg.sender == tokenOwner || isApprovedForAll(tokenOwner, msg.sender), "Not authorized");
        _tokenApprovals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }
    
    function getApproved(uint256 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "Collectible does not exist");
        return _tokenApprovals[tokenId];
    }
    
    function setApprovalForAll(address operator, bool approved) public {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
    
    function isApprovedForAll(address tokenOwner, address operator) public view returns (bool) {
        return _operatorApprovals[tokenOwner][operator];
    }
    
    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Transfer not authorized");
        require(ownerOf(tokenId) == from, "From address mismatch");
        require(to != address(0), "Transfer to zero address");
        require(!_listedForSale[tokenId], "Cannot transfer listed collectible");
        
        _tokenApprovals[tokenId] = address(0);
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;
        
        _updateUserCollectibles(from, to, tokenId);
        
        emit Transfer(from, to, tokenId);
    }
    
    // Collection Management
    
    function createCollection(string memory collectionName) public returns (uint256) {
        _collectionIdCounter++;
        uint256 newCollectionId = _collectionIdCounter;
        
        collections[newCollectionId] = Collection({
            collectionId: newCollectionId,
            collectionName: collectionName,
            creator: msg.sender,
            tokenIds: new uint256[](0),
            totalSupply: 0,
            active: true
        });
        
        _creatorCollections[msg.sender].push(newCollectionId);
        
        emit CollectionCreated(newCollectionId, collectionName, msg.sender);
        return newCollectionId;
    }
    
    // Minting Functions
    
    function mintCollectible(
        string memory uri,
        Rarity rarity,
        uint256 collectionId
    ) public returns (uint256) {
        require(collectionId == 0 || collections[collectionId].creator == msg.sender, "Not collection owner");
        
        _tokenIdCounter++;
        uint256 newTokenId = _tokenIdCounter;
        
        _balances[msg.sender] += 1;
        _owners[newTokenId] = msg.sender;
        _tokenURIs[newTokenId] = uri;
        _creators[newTokenId] = msg.sender;
        _rarities[newTokenId] = rarity;
        _collectionIds[newTokenId] = collectionId;
        _userCollectibles[msg.sender].push(newTokenId);
        
        if (collectionId > 0) {
            collections[collectionId].tokenIds.push(newTokenId);
            collections[collectionId].totalSupply += 1;
        }
        
        emit Transfer(address(0), msg.sender, newTokenId);
        emit CollectibleMinted(msg.sender, newTokenId, rarity);
        
        return newTokenId;
    }
    
    // Marketplace Functions
    
    function listForSale(uint256 tokenId, uint256 price) public {
        require(ownerOf(tokenId) == msg.sender, "Not collectible owner");
        require(price > 0, "Price must be greater than zero");
        
        _prices[tokenId] = price;
        _listedForSale[tokenId] = true;
        
        emit CollectibleListed(tokenId, price);
    }
    
    function unlistFromSale(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "Not collectible owner");
        _listedForSale[tokenId] = false;
    }
    
    function purchaseCollectible(uint256 tokenId) public payable nonReentrant {
        require(_listedForSale[tokenId], "Collectible not for sale");
        require(msg.value >= _prices[tokenId], "Insufficient payment");
        
        address seller = ownerOf(tokenId);
        address creator = _creators[tokenId];
        uint256 price = _prices[tokenId];
        
        // Calculate distributions
        uint256 platformCut = (price * platformFee) / FEE_DENOMINATOR;
        uint256 royaltyCut = (price * creatorRoyalty) / FEE_DENOMINATOR;
        uint256 sellerAmount = price - platformCut - royaltyCut;
        
        // Update state
        _listedForSale[tokenId] = false;
        _tokenApprovals[tokenId] = address(0);
        _balances[seller] -= 1;
        _balances[msg.sender] += 1;
        _owners[tokenId] = msg.sender;
        
        _updateUserCollectibles(seller, msg.sender, tokenId);
        
        // Transfer funds
        payable(seller).transfer(sellerAmount);
        payable(creator).transfer(royaltyCut);
        payable(owner).transfer(platformCut);
        
        // Refund excess
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
        
        emit Transfer(seller, msg.sender, tokenId);
        emit CollectibleSold(tokenId, msg.sender, seller, price);
        emit RoyaltyPaid(tokenId, creator, royaltyCut);
    }
    
    // Administrative Functions
    
    function setPlatformFee(uint256 newFee) public onlyOwner {
        require(newFee <= 1000, "Fee too high");
        platformFee = newFee;
    }
    
    function setCreatorRoyalty(uint256 newRoyalty) public onlyOwner {
        require(newRoyalty <= 1500, "Royalty too high");
        creatorRoyalty = newRoyalty;
    }
    
    function withdrawFees() public onlyOwner nonReentrant {
        payable(owner).transfer(address(this).balance);
    }
    
    // Query Functions
    
    function getRarity(uint256 tokenId) public view returns (Rarity) {
        require(_owners[tokenId] != address(0), "Collectible does not exist");
        return _rarities[tokenId];
    }
    
    function getCreator(uint256 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "Collectible does not exist");
        return _creators[tokenId];
    }
    
    function getPrice(uint256 tokenId) public view returns (uint256) {
        return _prices[tokenId];
    }
    
    function isListed(uint256 tokenId) public view returns (bool) {
        return _listedForSale[tokenId];
    }
    
    function getUserCollectibles(address user) public view returns (uint256[] memory) {
        return _userCollectibles[user];
    }
    
    function getCollectionTokens(uint256 collectionId) public view returns (uint256[] memory) {
        return collections[collectionId].tokenIds;
    }
    
    function totalCollectibles() public view returns (uint256) {
        return _tokenIdCounter;
    }
    
    // Helper Functions
    
    function _isApprovedOrOwner(address spender, uint256 tokenId) private view returns (bool) {
        address tokenOwner = ownerOf(tokenId);
        return (spender == tokenOwner || 
                getApproved(tokenId) == spender || 
                isApprovedForAll(tokenOwner, spender));
    }
    
    function _updateUserCollectibles(address from, address to, uint256 tokenId) private {
        // Remove from sender's collection
        uint256[] storage fromCollectibles = _userCollectibles[from];
        for (uint256 i = 0; i < fromCollectibles.length; i++) {
            if (fromCollectibles[i] == tokenId) {
                fromCollectibles[i] = fromCollectibles[fromCollectibles.length - 1];
                fromCollectibles.pop();
                break;
            }
        }
        
        // Add to receiver's collection
        _userCollectibles[to].push(tokenId);
    }
}
