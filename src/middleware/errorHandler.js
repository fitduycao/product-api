function errorHandler(error, req, res, next) {
  if (res.headersSent) return next(error);

  if (error.code === 11000) {
    return res.status(409).json({ message: 'pid đã tồn tại. Hãy dùng mã khác.' });
  }

  if (error.name === 'ValidationError') {
    const errors = Object.fromEntries(
      Object.entries(error.errors).map(([field, detail]) => [field, detail.message])
    );
    return res.status(400).json({ message: 'Dữ liệu không hợp lệ.', errors });
  }

  if (error.name === 'CastError') {
    return res.status(400).json({ message: `Giá trị ${error.path} không hợp lệ.` });
  }

  if (error.type === 'entity.parse.failed') {
    return res.status(400).json({ message: 'JSON không đúng cú pháp.' });
  }

  if (error.type === 'entity.too.large') {
    return res.status(413).json({ message: 'Body quá lớn.' });
  }

  if (error.status === 400) {
    return res.status(400).json({ message: error.message });
  }

  console.error(error.message);
  return res.status(500).json({ message: 'Lỗi máy chủ.' });
}

module.exports = errorHandler;
