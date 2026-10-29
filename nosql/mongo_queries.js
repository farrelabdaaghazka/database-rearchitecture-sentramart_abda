use sentramart;

db.products.find(
  { "attributes.color": "Red" },
  { product_name: 1, price: 1, attributes: 1, _id: 0 }
).explain("executionStats");

db.activity_logs.explain("executionStats").aggregate([
  {
    $match: {
      "event_type": { $in: ["add_to_cart", "checkout_start"] }
    }
  },
  {
    $group: {
      _id: "$event_type",
      total_events: { $sum: 1 },
      unique_users: { $addToSet: "$customer_id" }
    }
  }
]);

db.activity_logs.explain("executionStats").aggregate([
  {
    $match: {
      "event_type": "voucher_error"
    }
  },
  {
    $group: {
      _id: "$payload.error_code",
      error_count: { $sum: 1 }
    }
  },
  { $sort: { error_count: -1 } }
]);